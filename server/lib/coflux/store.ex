defmodule Coflux.Store do
  alias Exqlite.Sqlite3
  alias Coflux.Store.Migrations

  def open(project_id, environment) do
    dir = "data/#{project_id}/#{environment}"
    File.mkdir_p!(dir)
    {:ok, db} = Sqlite3.open(Path.join(dir, "store.sqlite"))
    :ok = Migrations.run(db)
    {:ok, db}
  end

  def close(db) do
    Sqlite3.close(db)
  end

  def start_session(db) do
    insert_one(db, :sessions, created_at: current_timestamp())
  end

  defp hash_targets(targets) do
    targets
    |> Enum.sort_by(fn {name, _} -> name end)
    |> :erlang.phash2()
  end

  defp insert_manifest(db, repository, targets, targets_hash, now) do
    {:ok, manifest_id} =
      insert_one(
        db,
        :manifests,
        repository: repository,
        targets_hash: targets_hash,
        created_at: now
      )

    {:ok, target_ids} =
      insert_many(
        db,
        :targets,
        {:manifest_id, :name, :type},
        Enum.map(targets, fn {name, data} ->
          type =
            case data.type do
              :task -> 0
              :step -> 1
              :sensor -> 2
            end

          {manifest_id, name, type}
        end)
      )

    {:ok, _} =
      insert_many(
        db,
        :parameters,
        {:target_id, :name, :position, :default_, :annotation},
        targets
        |> Enum.zip(target_ids)
        |> Enum.flat_map(fn {{_, data}, target_id} ->
          data.parameters
          |> Enum.with_index()
          |> Enum.map(fn {{name, default, annotation}, index} ->
            {target_id, name, index, default, annotation}
          end)
        end)
      )

    {:ok, manifest_id}
  end

  def get_or_create_manifest(db, repository, targets) do
    now = current_timestamp()
    targets_hash = hash_targets(targets)

    with_transaction(db, fn ->
      case query_one(
             db,
             """
             SELECT id
             FROM manifests
             WHERE repository = ?1 AND targets_hash = ?2
             """,
             {repository, targets_hash}
           ) do
        {:ok, nil} ->
          insert_manifest(db, repository, targets, targets_hash, now)

        {:ok, {manifest_id}} ->
          {:ok, manifest_id}
      end
    end)
  end

  def record_session_manifest(db, session_id, manifest_id) do
    now = current_timestamp()

    {:ok, _} =
      insert_one(db, :session_manifests,
        session_id: session_id,
        manifest_id: manifest_id,
        created_at: now
      )

    :ok
  end

  def start_run(db, repository, target, arguments, opts \\ []) do
    idempotency_key = Keyword.get(opts, :idempotency_key)
    parent_id = Keyword.get(opts, :parent_id)
    priority = Keyword.get(opts, :priority, 0)
    execute_after = Keyword.get(opts, :execute_after)
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, run_id} = insert_run(db, parent_id, idempotency_key, now)
      {:ok, step_id} = insert_step(db, run_id, nil, repository, target, priority, nil, now)
      :ok = insert_arguments(db, step_id, arguments)
      sequence = 1
      {:ok, execution_id} = insert_execution(db, execute_after, now)
      {:ok, _} = insert_step_execution(db, step_id, sequence, execution_id)
      {:ok, run_id, step_id, execution_id, sequence, now}
    end)
  end

  def get_run_id_for_step(db, step_id) do
    {:ok, [{run_id}]} =
      query(
        db,
        """
        SELECT run_id
        FROM steps
        WHERE id = ?1
        """,
        {step_id}
      )

    {:ok, run_id}
  end

  def get_run_id_for_step_execution(db, execution_id) do
    {:ok, [{run_id}]} =
      query(
        db,
        """
        SELECT s.run_id
        FROM steps AS s
        INNER JOIN step_executions AS se ON se.step_id = s.id
        WHERE se.execution_id = ?1
        """,
        {execution_id}
      )

    {:ok, run_id}
  end

  def schedule_step(db, run_id, parent_id, repository, target, arguments, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0)
    execute_after = Keyword.get(opts, :execute_after)
    cache_key = Keyword.get(opts, :cache_key)
    now = current_timestamp()

    with_transaction(db, fn ->
      cached_execution_id =
        if cache_key do
          case find_cached_execution(db, cache_key) do
            {:ok, cached_execution_id} ->
              cached_execution_id
          end
        end

      # TODO: validate parent belongs to run?
      {:ok, step_id} =
        insert_step(
          db,
          run_id,
          parent_id,
          repository,
          target,
          priority,
          unless(cached_execution_id, do: cache_key),
          now
        )

      :ok = insert_arguments(db, step_id, arguments)

      {execution_id, sequence} =
        if cached_execution_id do
          {:ok, _} = insert_cached_execution(db, step_id, cached_execution_id, now)
          {nil, nil}
        else
          sequence = 1
          {:ok, execution_id} = insert_execution(db, execute_after, now)
          {:ok, _} = insert_step_execution(db, step_id, sequence, execution_id)
          {execution_id, sequence}
        end

      {:ok, step_id, execution_id, sequence, now, cached_execution_id}
    end)
  end

  def rerun_step(db, step_id) do
    with_transaction(db, fn ->
      now = current_timestamp()
      {:ok, sequence} = get_next_step_execution_sequence(db, step_id)
      {:ok, execution_id} = insert_execution(db, nil, now)
      {:ok, _} = insert_step_execution(db, step_id, sequence, execution_id)
      {:ok, execution_id, sequence, now}
    end)
  end

  def iterate_sensor(db, sensor_activation_id) do
    with_transaction(db, fn ->
      now = current_timestamp()
      {:ok, sequence} = get_next_sensor_execution_sequence(db, sensor_activation_id)
      {:ok, execution_id} = insert_execution(db, nil, now)
      {:ok, _} = insert_sensor_execution(db, sensor_activation_id, sequence, execution_id)
      {:ok, execution_id, sequence, now}
    end)
  end

  def assign_execution(db, execution_id, session_id) do
    now = current_timestamp()

    {:ok, _} =
      insert_one(
        db,
        :assignments,
        execution_id: execution_id,
        session_id: session_id,
        created_at: now
      )

    {:ok, now}
  end

  def record_dependency(db, execution_id, dependency_id) do
    {:ok, _} =
      insert_one(
        db,
        :dependencies,
        execution_id: execution_id,
        dependency_id: dependency_id,
        created_at: current_timestamp()
      )

    :ok
  end

  def record_hearbeats(db, executions) do
    with_transaction(db, fn ->
      now = current_timestamp()

      insert_many(
        db,
        :heartbeats,
        {:execution_id, :status, :created_at},
        Enum.map(executions, fn {execution_id, status} ->
          {execution_id, status, now}
        end)
      )

      {:ok, now}
    end)
  end

  def record_result(db, execution_id, result) do
    now = current_timestamp()

    case insert_result(db, execution_id, 0, result, now) do
      {:ok, _} ->
        {:ok, now}
    end
  end

  def get_execution_result(db, execution_id) do
    case query_one(
           db,
           """
           SELECT type, format, value, created_at
           FROM results
           WHERE execution_id = ?1 AND sequence = 0
           """,
           {execution_id}
         ) do
      {:ok, {type, format, value, created_at}} ->
        result =
          case type do
            0 -> {:error, value, nil}
            1 -> {:reference, value}
            2 -> {:raw, format, value}
            3 -> {:blob, format, value}
            4 -> :abandoned
          end

        {:ok, {result, created_at}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  def record_cursor(db, execution_id, result) do
    with_transaction(db, fn ->
      sequence =
        case query_one(
               db,
               """
               SELECT MAX(sequence)
               FROM results
               WHERE execution_id = ?1 AND sequence != 0
               """,
               {execution_id}
             ) do
          {:ok, {nil}} ->
            1

          {:ok, {max_sequence}} ->
            max_sequence + 1
        end

      now = current_timestamp()

      case insert_result(db, execution_id, sequence, result, now) do
        {:ok, _} ->
          {:ok, now}
      end
    end)
  end

  def get_unassigned_executions(db) do
    # TODO: order by priority?
    query(
      db,
      """
      SELECT e.id, ste.step_id, sne.sensor_activation_id
      FROM executions AS e
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN step_executions AS ste ON ste.execution_id = e.id
      LEFT JOIN sensor_executions AS sne ON sne.execution_id = e.id
      WHERE a.created_at IS NULL AND (e.execute_after IS NULL OR e.execute_after >= ?1)
      """,
      {current_timestamp()}
    )
  end

  def get_pending_assignments(db) do
    query(
      db,
      """
      SELECT a.execution_id, a.created_at, (SELECT MAX(created_at) FROM heartbeats WHERE execution_id = a.execution_id)
      FROM assignments AS a
      LEFT JOIN results AS r ON r.execution_id = a.execution_id AND r.sequence = 0
      WHERE r.created_at IS NULL
      """
    )
  end

  def activate_sensor(db, repository, target) do
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, sensor_activation_id} =
        insert_one(db, :sensor_activations,
          repository: repository,
          target: target,
          created_at: now
        )

      sequence = 1
      {:ok, execution_id} = insert_execution(db, nil, now)
      insert_sensor_execution(db, sensor_activation_id, sequence, execution_id)
      {:ok, sensor_activation_id, sequence, execution_id}
    end)
  end

  def deactivate_sensor(db, repository, target) do
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, rows} =
        query(
          db,
          """
          SELECT sa.id
          FROM sensor_activations AS sa
          LEFT JOIN sensor_deactivations AS sd ON sd.sensor_activation_id = sa.id
          WHERE sa.repository = ?1 AND sa.target = ?2 AND sd.created_at IS NOT NULL
          """,
          {repository, target}
        )

      case insert_many(
             db,
             :sensor_deactivations,
             {:sensor_activation_id, :created_at},
             Enum.map(rows, fn {sensor_activation_id} -> {sensor_activation_id, now} end)
           ) do
        {:ok, _} ->
          :ok
      end
    end)
  end

  def get_activated_sensors(db) do
    query(
      db,
      """
      SELECT sa.id, (
        SELECT se.execution_id
        FROM sensor_executions AS se
        INNER JOIN executions AS e ON se.execution_id = e.id
        LEFT JOIN results AS re ON re.execution_id = se.execution_id AND re.sequence = 0
        WHERE se.sensor_activation_id = sa.id AND re.created_at IS NULL
        ORDER BY e.created_at DESC
        LIMIT 1
      )
      FROM sensor_activations AS sa
      LEFT JOIN sensor_deactivations AS sd ON sd.sensor_activation_id = sa.id
      WHERE sd.created_at IS NULL
      """
    )
  end

  def get_sensor_activation(db, repository, target_name) do
    query_one(
      db,
      """
      SELECT sa.id
      FROM sensor_activations AS sa
      LEFT JOIN sensor_deactivations AS sd ON sd.sensor_activation_id = sa.id
      WHERE sa.repository = ?1 AND sa.target = ?2 AND sd.created_at IS NULL
      """,
      {repository, target_name}
    )
  end

  def get_sensor_activation_by_id(db, sensor_activation_id) do
    query_one(
      db,
      """
      SELECT sa.repository, sa.target, sd.created_at
      FROM sensor_activations AS sa
      LEFT JOIN sensor_deactivations AS sd ON sd.sensor_activation_id = sa.id
      WHERE sa.id = ?1
      """,
      {sensor_activation_id}
    )
  end

  def get_sensor_activation_for_execution_id(db, execution_id) do
    query_one(
      db,
      """
      SELECT sa.repository, sa.target
      FROM sensor_activations AS sa
      INNER JOIN sensor_executions AS se ON se.sensor_activation_id = sa.id
      WHERE se.execution_id = ?1
      """,
      {execution_id}
    )
  end

  def get_latest_targets(db) do
    # TODO: reduce number of queries

    {:ok, manifests} =
      query(
        db,
        """
        SELECT id, repository
        FROM manifests
        GROUP BY repository
        ORDER BY repository, created_at DESC
        """
      )

    targets =
      Map.new(manifests, fn {manifest_id, repository} ->
        {:ok, rows} =
          query(
            db,
            """
            SELECT id, name, type
            FROM targets
            WHERE manifest_id = ?1
            """,
            {manifest_id}
          )

        {repository,
         Map.new(rows, fn {target_id, target, type} ->
           {:ok, parameters} =
             query(
               db,
               """
               SELECT name, default_, annotation
               FROM parameters
               WHERE target_id = ?1
               ORDER BY position
               """,
               {target_id}
             )

           type =
             case type do
               0 -> :task
               1 -> :step
               2 -> :sensor
             end

           {target, %{type: type, parameters: parameters}}
         end)}
      end)

    {:ok, targets}
  end

  def get_task_runs(db, repository, target, limit \\ 50) do
    query(
      db,
      """
      SELECT r.id, r.created_at
      FROM runs as r
      INNER JOIN steps AS s ON s.run_id = r.id
      WHERE s.repository = ?1
        AND s.target = ?2
        AND s.parent_id IS NULL
      ORDER BY r.created_at DESC
      LIMIT ?3
      """,
      {repository, target, limit}
    )
  end

  def get_sensor_executions(db, repository, target, limit \\ 10) do
    query(
      db,
      """
      SELECT e.id, e.created_at
      FROM sensor_executions AS se
      INNER JOIN executions AS e ON e.id = se.execution_id
      INNER JOIN sensor_activations AS sa ON sa.id = se.sensor_activation_id
      WHERE sa.repository = ?1 AND sa.target = ?2
      ORDER BY e.created_at DESC
      LIMIT ?3
      """,
      {repository, target, limit}
    )
  end

  def get_sensor_runs(db, repository, target, limit \\ 50) do
    query(
      db,
      """
      SELECT r.id, r.created_at, s.repository, s.target
      FROM runs AS r
      INNER JOIN executions AS e ON e.id = r.parent_id
      INNER JOIN sensor_executions AS se ON se.execution_id = e.id
      INNER JOIN sensor_activations AS sa ON sa.id = se.sensor_activation_id
      INNER JOIN steps AS s ON s.run_id = r.id AND s.parent_id IS NULL
      WHERE sa.repository = ?1 AND sa.target = ?2
      ORDER BY r.created_at DESC
      LIMIT ?3
      """,
      {repository, target, limit}
    )
  end

  def get_run(db, run_id) do
    query_one(
      db,
      """
      SELECT parent_id, created_at
      FROM runs
      WHERE id = ?1
      """,
      {run_id}
    )
  end

  def get_run_steps(db, run_id) do
    query(
      db,
      """
      SELECT s.id, s.parent_id, s.repository, s.target, s.created_at, ce.execution_id
      FROM steps AS s
      LEFT JOIN cached_executions AS ce ON ce.step_id = s.id
      WHERE s.run_id = ?1
      """,
      {run_id}
    )
  end

  def get_step(db, step_id) do
    query_one(
      db,
      """
      SELECT run_id, repository, target
      FROM steps
      WHERE id = ?1
      """,
      {step_id}
    )
  end

  def get_step_executions(db, step_id) do
    query(
      db,
      """
      SELECT e.id, se.sequence, e.execute_after, e.created_at, a.session_id, a.created_at
      FROM executions AS e
      INNER JOIN step_executions AS se ON se.execution_id = e.id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      WHERE se.step_id = ?1
      """,
      {step_id}
    )
  end

  def get_step_arguments(db, step_id) do
    case query(
           db,
           """
           SELECT type, format, value
           FROM arguments
           WHERE step_id = ?1
           ORDER BY position
           """,
           {step_id}
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn {type, format, value} ->
           case type do
             1 -> {:reference, value}
             2 -> {:raw, format, value}
             3 -> {:blob, format, value}
           end
         end)}
    end
  end

  def get_execution_dependencies(db, execution_id) do
    query(
      db,
      """
      SELECT dependency_id
      FROM dependencies
      WHERE execution_id = ?1
      """,
      {execution_id}
    )
  end

  defp find_cached_execution(db, cache_key) do
    query_one(
      db,
      """
      SELECT e.id
      FROM steps AS s
      INNER JOIN step_executions AS se ON se.step_id = s.id
      INNER JOIN executions AS e ON e.id = se.execution_id
      LEFT JOIN results AS r ON r.execution_id = e.id AND r.sequence = 0
      WHERE s.cache_key = ?1 AND (r.type IS NULL OR r.type IN (1, 2, 3))
      ORDER BY e.created_at DESC
      LIMIT 1
      """,
      {cache_key}
    )
  end

  defp insert_run(db, parent_id, idempotency_key, created_at) do
    insert_one(db, :runs,
      parent_id: parent_id,
      idempotency_key: idempotency_key,
      created_at: created_at
    )
  end

  defp insert_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         priority,
         cache_key,
         now
       ) do
    insert_one(
      db,
      :steps,
      run_id: run_id,
      parent_id: parent_id,
      repository: repository,
      target: target,
      priority: priority,
      cache_key: cache_key,
      created_at: now
    )
  end

  defp insert_arguments(db, step_id, arguments) do
    case insert_many(
           db,
           :arguments,
           {:step_id, :position, :type, :format, :value},
           Enum.map(Enum.with_index(arguments), fn {argument, index} ->
             {type, format, value} =
               case argument do
                 {:reference, execution_id} -> {1, nil, execution_id}
                 {:raw, format, data} -> {2, format, data}
                 {:blob, format, hash} -> {3, format, hash}
               end

             {step_id, index, type, format, value}
           end)
         ) do
      {:ok, _} -> :ok
    end
  end

  defp get_next_step_execution_sequence(db, step_id) do
    {:ok, [{last_sequence}]} =
      query(
        db,
        """
        SELECT MAX(sequence)
        FROM step_executions
        WHERE step_id = ?1
        """,
        {step_id}
      )

    {:ok, last_sequence + 1}
  end

  def get_next_sensor_execution_sequence(db, sensor_activation_id) do
    {:ok, [{last_sequence}]} =
      query(
        db,
        """
        SELECT MAX(sequence)
        FROM sensor_executions
        WHERE sensor_activation_id = ?1
        """,
        {sensor_activation_id}
      )

    {:ok, last_sequence + 1}
  end

  defp insert_execution(db, execute_after, created_at) do
    insert_one(
      db,
      :executions,
      execute_after: execute_after,
      created_at: created_at
    )
  end

  defp insert_step_execution(db, step_id, sequence, execution_id) do
    insert_one(
      db,
      :step_executions,
      step_id: step_id,
      sequence: sequence,
      execution_id: execution_id
    )
  end

  defp insert_sensor_execution(db, sensor_activation_id, sequence, execution_id) do
    insert_one(
      db,
      :sensor_executions,
      sensor_activation_id: sensor_activation_id,
      sequence: sequence,
      execution_id: execution_id
    )
  end

  defp insert_cached_execution(db, step_id, cached_execution_id, created_at) do
    insert_one(
      db,
      :cached_executions,
      step_id: step_id,
      execution_id: cached_execution_id,
      created_at: created_at
    )
  end

  defp insert_result(db, execution_id, sequence, result, created_at) do
    {type, format, value} =
      case result do
        # TODO: handle details
        {:error, error, _details} -> {0, nil, error}
        {:reference, execution_id} -> {1, nil, execution_id}
        {:raw, format, data} -> {2, format, data}
        {:blob, format, hash} -> {3, format, hash}
        :abandoned -> {4, nil, nil}
      end

    insert_one(
      db,
      :results,
      execution_id: execution_id,
      sequence: sequence,
      type: type,
      format: format,
      value: value,
      created_at: created_at
    )
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end

  defp with_prepare(db, sql, fun) do
    {:ok, statement} = Sqlite3.prepare(db, sql)
    result = fun.(statement)
    :ok = Sqlite3.release(db, statement)
    result
  end

  defp with_transaction(db, fun) do
    :ok = Sqlite3.execute(db, "BEGIN")
    result = fun.()
    :ok = Sqlite3.execute(db, "COMMIT")
    result
  end

  defp insert_one(db, table, values) do
    {fields, values} = Enum.unzip(values)
    {:ok, [id]} = insert_many(db, table, List.to_tuple(fields), [List.to_tuple(values)])
    {:ok, id}
  end

  defp insert_many(db, table, fields, values) do
    {fields, indexes} =
      fields
      |> Tuple.to_list()
      |> Enum.with_index(1)
      |> Enum.unzip()

    fields = Enum.join(fields, ", ")
    placeholders = Enum.map_join(indexes, ", ", fn index -> "?#{index}" end)
    sql = "INSERT INTO #{table} (#{fields}) VALUES (#{placeholders})"

    with_prepare(db, sql, fn statement ->
      ids =
        Enum.map(values, fn row ->
          :ok = Sqlite3.bind(db, statement, Tuple.to_list(row))
          :done = Sqlite3.step(db, statement)
          {:ok, id} = Sqlite3.last_insert_rowid(db)
          id
        end)

      {:ok, ids}
    end)
  end

  defp query(db, sql, args \\ {}) do
    with_prepare(db, sql, fn statement ->
      :ok = Sqlite3.bind(db, statement, Tuple.to_list(args))
      {:ok, rows} = Sqlite3.fetch_all(db, statement)
      {:ok, Enum.map(rows, &List.to_tuple/1)}
    end)
  end

  defp query_one(db, sql, args) do
    case query(db, sql, args) do
      {:ok, [row]} ->
        {:ok, row}

      {:ok, []} ->
        {:ok, nil}
    end
  end
end

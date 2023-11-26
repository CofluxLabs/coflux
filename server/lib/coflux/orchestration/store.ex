defmodule Coflux.Orchestration.Store do
  alias Exqlite.Sqlite3
  alias Coflux.Orchestration.Store.{Migrations, Models}

  @id_chars String.codepoints("bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ23456789")

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
    case generate_external_id(db, :sessions, 30) do
      {:ok, external_id} ->
        case insert_one(db, :sessions, external_id: external_id, created_at: current_timestamp()) do
          {:ok, session_id} ->
            {:ok, session_id, external_id}
        end
    end
  end

  defp generate_external_id(db, table, length, prefix \\ "") do
    id = prefix <> Enum.map_join(0..length, fn _ -> Enum.random(@id_chars) end)

    case query(db, "SELECT id FROM #{table} WHERE external_id = ?1", {id}) do
      {:ok, []} -> {:ok, id}
      {:ok, _} -> generate_external_id(db, table, length + 1, prefix)
    end
  end

  defp hash_targets(targets) do
    targets
    |> Enum.sort_by(fn {name, _} -> name end)
    |> :erlang.phash2()
  end

  defp insert_manifest(db, repository, targets, targets_hash) do
    {:ok, manifest_id} =
      insert_one(
        db,
        :manifests,
        repository: repository,
        targets_hash: targets_hash
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
          insert_manifest(db, repository, targets, targets_hash)

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
    deduplicate_key = Keyword.get(opts, :deduplicate_key)
    retry_count = Keyword.get(opts, :retry_count, 0)
    retry_delay_min = Keyword.get(opts, :retry_delay_min, 0)
    retry_delay_max = Keyword.get(opts, :retry_delay_max, retry_delay_min)
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, run_id, external_run_id} = insert_run(db, parent_id, idempotency_key, now)

      {:ok, step_id, external_step_id} =
        insert_step(
          db,
          run_id,
          nil,
          repository,
          target,
          priority,
          nil,
          deduplicate_key,
          retry_count,
          retry_delay_min,
          retry_delay_max,
          now
        )

      :ok = insert_arguments(db, step_id, arguments)
      sequence = 1
      {:ok, execution_id} = insert_execution(db, execute_after, now)
      {:ok, _} = insert_step_execution(db, step_id, sequence, execution_id)
      {:ok, run_id, external_run_id, step_id, external_step_id, execution_id, sequence, now}
    end)
  end

  def get_step_by_external_id(db, external_id) do
    query_one(
      db,
      """
      SELECT
        s.id,
        s.external_id,
        s.run_id,
        s.parent_id,
        s.repository,
        s.target,
        s.priority,
        s.cache_key,
        s.retry_count,
        s.retry_delay_min,
        s.retry_delay_max,
        s.created_at
      FROM steps as s
      WHERE external_id = ?1
      """,
      {external_id},
      Models.Step
    )
  end

  def get_step_for_execution(db, execution_id) do
    query_one!(
      db,
      """
      SELECT
        s.id,
        s.external_id,
        s.run_id,
        s.parent_id,
        s.repository,
        s.target,
        s.priority,
        s.cache_key,
        s.retry_count,
        s.retry_delay_min,
        s.retry_delay_max,
        s.created_at
      FROM steps AS s
      INNER JOIN step_executions AS se ON se.step_id = s.id
      WHERE se.execution_id = ?1
      """,
      {execution_id},
      Models.Step
    )
  end

  def schedule_step(db, run_id, parent_id, repository, target, arguments, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0)
    execute_after = Keyword.get(opts, :execute_after)
    cache_key = Keyword.get(opts, :cache_key)
    deduplicate_key = Keyword.get(opts, :deduplicate_key)
    retry_count = Keyword.get(opts, :retry_count, 0)
    retry_delay_min = Keyword.get(opts, :retry_delay_min, 0)
    retry_delay_max = Keyword.get(opts, :retry_delay_max, retry_delay_min)
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
      {:ok, step_id, external_step_id} =
        insert_step(
          db,
          run_id,
          parent_id,
          repository,
          target,
          priority,
          unless(cached_execution_id, do: cache_key),
          deduplicate_key,
          retry_count,
          retry_delay_min,
          retry_delay_max,
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

      {:ok, step_id, external_step_id, execution_id, sequence, now, cached_execution_id}
    end)
  end

  def rerun_step(db, step_id, execute_after \\ nil) do
    with_transaction(db, fn ->
      now = current_timestamp()
      # TODO: cancel pending executions for step?
      {:ok, sequence} = get_next_step_execution_sequence(db, step_id)
      {:ok, execution_id} = insert_execution(db, execute_after, now)
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

  def record_result(db, execution_id, result, retry_id \\ nil) do
    now = current_timestamp()

    case insert_result(db, execution_id, result, retry_id, now) do
      {:ok, _} ->
        {:ok, now}
    end
  end

  def get_execution_result(db, execution_id) do
    case query_one(
           db,
           """
           SELECT type, format, value, retry_id, created_at
           FROM results
           WHERE execution_id = ?1
           """,
           {execution_id}
         ) do
      {:ok, {type, format, value, retry_id, created_at}} ->
        result = build_result(type, format, value)
        {:ok, {result, retry_id, created_at}}

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
               FROM cursors
               WHERE execution_id = ?1
               """,
               {execution_id}
             ) do
          {:ok, {nil}} ->
            1

          {:ok, {max_sequence}} ->
            max_sequence + 1
        end

      now = current_timestamp()

      case insert_cursor(db, execution_id, sequence, result, now) do
        {:ok, _} ->
          {:ok, now}
      end
    end)
  end

  def get_latest_sensor_activation_cursor(db, sensor_activation_id) do
    case query(
           db,
           """
           SELECT type, format, value
           FROM cursors AS c
           INNER JOIN sensor_executions AS se ON se.execution_id = c.execution_id
           WHERE se.sensor_activation_id = ?1
           ORDER BY se.sequence DESC, c.sequence DESC
           LIMIT 1
           """,
           {sensor_activation_id}
         ) do
      {:ok, [{type, format, value}]} ->
        result = build_result(type, format, value)
        {:ok, result}

      {:ok, []} ->
        {:ok, nil}
    end
  end

  def get_unassigned_executions(db) do
    query(
      db,
      """
      SELECT
        e.id,
        s.id,
        s.run_id,
        s.repository,
        s.target,
        s.deduplicate_key,
        sne.sensor_activation_id,
        e.execute_after
      FROM executions AS e
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN step_executions AS ste ON ste.execution_id = e.id
      LEFT JOIN steps AS s ON s.id = ste.step_id
      LEFT JOIN sensor_executions AS sne ON sne.execution_id = e.id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE a.created_at IS NULL AND r.created_at IS NULL
      ORDER BY e.execute_after, e.created_at
      """
    )
  end

  def get_pending_assignments(db) do
    query(
      db,
      """
      SELECT a.execution_id, a.created_at, (SELECT MAX(created_at) FROM heartbeats WHERE execution_id = a.execution_id)
      FROM assignments AS a
      LEFT JOIN results AS r ON r.execution_id = a.execution_id
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
      {:ok, _} = insert_sensor_execution(db, sensor_activation_id, sequence, execution_id)
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
          WHERE sa.repository = ?1 AND sa.target = ?2 AND sd.created_at IS NULL
          """,
          {repository, target}
        )

      sensor_activation_ids =
        Enum.map(rows, fn {sensor_activation_id} -> sensor_activation_id end)

      case insert_many(
             db,
             :sensor_deactivations,
             {:sensor_activation_id, :created_at},
             Enum.map(sensor_activation_ids, &{&1, now})
           ) do
        {:ok, _} ->
          {:ok, sensor_activation_ids}
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
        LEFT JOIN results AS r ON r.execution_id = se.execution_id
        WHERE se.sensor_activation_id = sa.id AND r.created_at IS NULL
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
        FROM (
          SELECT m.id, m.repository
          FROM manifests AS m
          INNER JOIN session_manifests AS sm ON sm.manifest_id = m.id
          ORDER BY m.repository, sm.created_at DESC
        )
        GROUP BY repository
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
      SELECT r.external_id, r.created_at
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
      SELECT r.external_id, r.created_at, s.repository, s.target
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

  def get_run_by_external_id(db, external_id) do
    query_one(
      db,
      """
      SELECT id, parent_id, created_at
      FROM runs
      WHERE external_id = ?1
      """,
      {external_id}
    )
  end

  def get_run_by_execution(db, execution_id) do
    query_one(
      db,
      """
      SELECT r.external_id, s1.external_id, se.sequence, s2.repository, s2.target
      FROM step_executions AS se
      INNER JOIN steps AS s1 ON s1.id = se.step_id
      INNER JOIN steps AS s2 ON s2.run_id = s1.run_id AND s2.parent_id IS NULL
      INNER JOIN runs AS r ON r.id = s1.run_id
      WHERE se.execution_id = ?1
      """,
      {execution_id}
    )
  end

  def get_external_run_id_for_execution(db, execution_id) do
    query_one(
      db,
      """
      SELECT r.external_id
      FROM step_executions AS se
      INNER JOIN steps AS s ON s.id = se.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE se.execution_id = ?1
      """,
      {execution_id}
    )
  end

  def get_runs_by_parent(db, execution_id) do
    query(
      db,
      """
      SELECT r.external_id, s.repository, s.target
      FROM runs AS r
      INNER JOIN steps AS s ON s.run_id = r.id AND s.parent_id IS NULL
      WHERE r.parent_id = ?1
      """,
      {execution_id}
    )
  end

  def get_run_steps(db, run_id) do
    query(
      db,
      """
      SELECT s.id, s.external_id, s.parent_id, s.repository, s.target, s.created_at, ce.execution_id
      FROM steps AS s
      LEFT JOIN cached_executions AS ce ON ce.step_id = s.id
      WHERE s.run_id = ?1
      """,
      {run_id}
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
    case query(
           db,
           """
           SELECT e.id
           FROM steps AS s
           INNER JOIN step_executions AS se ON se.step_id = s.id
           INNER JOIN executions AS e ON e.id = se.execution_id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE s.cache_key = ?1 AND (r.type IS NULL OR r.type IN (1, 2, 3))
           ORDER BY e.created_at DESC
           LIMIT 1
           """,
           {cache_key}
         ) do
      {:ok, [{execution_id}]} ->
        {:ok, execution_id}

      {:ok, []} ->
        {:ok, nil}
    end
  end

  defp insert_run(db, parent_id, idempotency_key, created_at) do
    case generate_external_id(db, :runs, 2, "R") do
      {:ok, external_id} ->
        case insert_one(db, :runs,
               external_id: external_id,
               parent_id: parent_id,
               idempotency_key: idempotency_key,
               created_at: created_at
             ) do
          {:ok, run_id} ->
            {:ok, run_id, external_id}
        end
    end
  end

  defp insert_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         priority,
         cache_key,
         deduplicate_key,
         retry_count,
         retry_delay_min,
         retry_delay_max,
         now
       ) do
    case generate_external_id(db, :steps, 3, "S") do
      {:ok, external_id} ->
        case insert_one(
               db,
               :steps,
               external_id: external_id,
               run_id: run_id,
               parent_id: parent_id,
               repository: repository,
               target: target,
               priority: priority,
               cache_key: cache_key,
               deduplicate_key: deduplicate_key,
               retry_count: retry_count,
               retry_delay_min: retry_delay_min,
               retry_delay_max: retry_delay_max,
               created_at: now
             ) do
          {:ok, step_id} ->
            {:ok, step_id, external_id}
        end
    end
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
    case query(
           db,
           """
           SELECT MAX(sequence)
           FROM step_executions
           WHERE step_id = ?1
           """,
           {step_id}
         ) do
      {:ok, [{nil}]} ->
        {:ok, 1}

      {:ok, [{last_sequence}]} ->
        {:ok, last_sequence + 1}
    end
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

  defp parse_result(result) do
    case result do
      # TODO: handle details
      {:error, error, _details} -> {0, nil, error}
      {:reference, execution_id} -> {1, nil, execution_id}
      {:raw, format, data} -> {2, format, data}
      {:blob, format, hash} -> {3, format, hash}
      :abandoned -> {4, nil, nil}
      :cancelled -> {5, nil, nil}
      :duplicated -> {6, nil, nil}
    end
  end

  defp build_result(type, format, value) do
    case type do
      0 -> {:error, value, nil}
      1 -> {:reference, value}
      2 -> {:raw, format, value}
      3 -> {:blob, format, value}
      4 -> :abandoned
      5 -> :cancelled
      6 -> :duplicated
    end
  end

  defp insert_result(db, execution_id, result, retry_id, created_at) do
    {type, format, value} = parse_result(result)

    insert_one(
      db,
      :results,
      execution_id: execution_id,
      type: type,
      format: format,
      value: value,
      retry_id: retry_id,
      created_at: created_at
    )
  end

  defp insert_cursor(db, execution_id, sequence, result, created_at) do
    # TODO: check result isn't error/abandoned/cancelled?
    {type, format, value} = parse_result(result)

    insert_one(
      db,
      :cursors,
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
    if Enum.any?(values) do
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
    else
      {:ok, []}
    end
  end

  defp build(row, model, columns) do
    if model do
      keys = Enum.map(columns, &String.to_existing_atom/1)
      struct(model, Enum.zip(keys, row))
    else
      List.to_tuple(row)
    end
  end

  defp query(db, sql, args \\ {}, model \\ nil) do
    with_prepare(db, sql, fn statement ->
      :ok = Sqlite3.bind(db, statement, Tuple.to_list(args))
      {:ok, columns} = Sqlite3.columns(db, statement)
      {:ok, rows} = Sqlite3.fetch_all(db, statement)
      {:ok, Enum.map(rows, &build(&1, model, columns))}
    end)
  end

  defp query_one(db, sql, args, model \\ nil) do
    case query(db, sql, args, model) do
      {:ok, [row]} ->
        {:ok, row}

      {:ok, []} ->
        {:ok, nil}
    end
  end

  defp query_one!(db, sql, args, model) do
    case query(db, sql, args, model) do
      {:ok, [row]} ->
        {:ok, row}
    end
  end
end
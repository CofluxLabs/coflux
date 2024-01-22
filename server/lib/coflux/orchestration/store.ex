defmodule Coflux.Orchestration.Store do
  alias Exqlite.Sqlite3
  alias Coflux.Orchestration.Store.{Migrations, Models}
  alias Coflux.Utils

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
    with_transaction(db, fn ->
      case generate_external_id(db, :sessions, 30) do
        {:ok, external_id} ->
          case insert_one(db, :sessions, %{
                 external_id: external_id,
                 created_at: current_timestamp()
               }) do
            {:ok, session_id} ->
              {:ok, session_id, external_id}
          end
      end
    end)
  end

  defp generate_external_id(db, table, length, prefix \\ "") do
    id = Utils.generate_id(length, prefix)

    case query(db, "SELECT id FROM #{table} WHERE external_id = ?1", {id}) do
      {:ok, []} -> {:ok, id}
      {:ok, _} -> generate_external_id(db, table, length + 1, prefix)
    end
  end

  defp insert_manifest(db, repository, targets, targets_hash) do
    {:ok, manifest_id} =
      insert_one(db, :manifests, %{
        repository: repository,
        targets_hash: targets_hash
      })

    {:ok, target_ids} =
      insert_many(
        db,
        :targets,
        {:manifest_id, :name, :type},
        Enum.map(targets, fn {name, data} ->
          type =
            case data.type do
              :workflow -> 0
              :task -> 1
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
    targets = Enum.sort_by(targets, fn {name, _} -> name end)
    targets_hash = :erlang.phash2(targets)

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
    with_transaction(db, fn ->
      now = current_timestamp()

      {:ok, _} =
        insert_one(db, :session_manifests, %{
          session_id: session_id,
          manifest_id: manifest_id,
          created_at: now
        })

      :ok
    end)
  end

  def start_run(db, repository, target, arguments, opts \\ []) do
    idempotency_key = Keyword.get(opts, :idempotency_key)
    parent_id = Keyword.get(opts, :parent_id)
    recurrent = Keyword.get(opts, :recurrent)
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, run_id, external_run_id} = insert_run(db, parent_id, idempotency_key, recurrent, now)

      {:ok, step_id, external_step_id, execution_id, sequence, execution_type, now, false,
       child_added} =
        do_schedule_step(db, run_id, parent_id, repository, target, arguments, true, now, opts)

      {:ok, run_id, external_run_id, step_id, external_step_id, execution_id, sequence,
       execution_type, now, child_added}
    end)
  end

  def get_step_by_external_id(db, external_id) do
    query_one(
      db,
      """
      SELECT
        id,
        external_id,
        run_id,
        type,
        repository,
        target,
        priority,
        cache_key,
        retry_count,
        retry_delay_min,
        retry_delay_max,
        created_at
      FROM steps
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
        s.type,
        s.repository,
        s.target,
        s.priority,
        s.cache_key,
        s.retry_count,
        s.retry_delay_min,
        s.retry_delay_max,
        s.created_at
      FROM steps AS s
      INNER JOIN attempts AS a ON a.step_id = s.id
      WHERE a.execution_id = ?1 AND a.type = 0
      """,
      {execution_id},
      Models.Step
    )
  end

  def schedule_step(db, run_id, parent_id, repository, target, arguments, opts \\ []) do
    now = current_timestamp()

    with_transaction(db, fn ->
      do_schedule_step(db, run_id, parent_id, repository, target, arguments, false, now, opts)
    end)
  end

  defp do_schedule_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         arguments,
         is_initial,
         now,
         opts
       ) do
    priority = Keyword.get(opts, :priority, 0)
    execute_after = Keyword.get(opts, :execute_after)
    cache_key = Keyword.get(opts, :cache_key)
    defer_key = Keyword.get(opts, :defer_key)
    memo_key = Keyword.get(opts, :memo_key)
    retry_count = Keyword.get(opts, :retry_count, 0)
    retry_delay_min = Keyword.get(opts, :retry_delay_min, 0)
    retry_delay_max = Keyword.get(opts, :retry_delay_max, retry_delay_min)

    memoised_execution =
      if memo_key do
        case find_memoised_execution(db, run_id, memo_key) do
          {:ok, memoised_execution} -> memoised_execution
        end
      end

    {step_id, external_step_id, execution_id, sequence, execution_type, now, memoised} =
      case memoised_execution do
        {step_id, external_step_id, execution_id, sequence, execution_type, now} ->
          {step_id, external_step_id, execution_id, sequence, execution_type, now, true}

        nil ->
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
              if(is_initial, do: 0, else: 1),
              repository,
              target,
              priority,
              cache_key,
              defer_key,
              memo_key,
              retry_count,
              retry_delay_min,
              retry_delay_max,
              now
            )

          :ok = insert_arguments(db, step_id, get_or_create_arguments(db, arguments))

          sequence = 1

          {execution_id, execution_type} =
            if cached_execution_id do
              {cached_execution_id, 1}
            else
              {:ok, execution_id} = insert_execution(db, execute_after, now)
              {execution_id, 0}
            end

          {:ok, _} =
            insert_attempt(db, step_id, sequence, execution_id, execution_type, now)

          {step_id, external_step_id, execution_id, sequence, execution_type, now, false}
      end

    child_added =
      if parent_id do
        {:ok, id} = insert_child(db, parent_id, step_id, now)
        !is_nil(id)
      else
        false
      end

    {:ok, step_id, external_step_id, execution_id, sequence, execution_type, now, memoised,
     child_added}
  end

  def rerun_step(db, step_id, execute_after \\ nil) do
    with_transaction(db, fn ->
      now = current_timestamp()
      # TODO: cancel pending executions for step?
      {:ok, sequence} = get_next_attempt_sequence(db, step_id)
      {:ok, execution_id} = insert_execution(db, execute_after, now)
      execution_type = 0
      {:ok, _} = insert_attempt(db, step_id, sequence, execution_id, execution_type, now)
      {:ok, execution_id, sequence, execution_type, now}
    end)
  end

  def assign_execution(db, execution_id, session_id) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {:ok, _} =
        insert_one(db, :assignments, %{
          execution_id: execution_id,
          session_id: session_id,
          created_at: now
        })

      {:ok, now}
    end)
  end

  def record_dependency(db, execution_id, dependency_id) do
    with_transaction(db, fn ->
      insert_one(
        db,
        :dependencies,
        %{
          execution_id: execution_id,
          dependency_id: dependency_id,
          created_at: current_timestamp()
        },
        on_conflict: "DO NOTHING"
      )
    end)
  end

  def record_checkpoint(db, execution_id, arguments) do
    with_transaction(db, fn ->
      sequence =
        case query_one(
               db,
               """
               SELECT MAX(sequence)
               FROM checkpoints
               WHERE execution_id = ?1
               """,
               {execution_id}
             ) do
          {:ok, {nil}} -> 1
          {:ok, {max_sequence}} -> max_sequence + 1
        end

      now = current_timestamp()

      {:ok, checkpoint_id} = insert_checkpoint(db, execution_id, sequence, now)

      {:ok, _} =
        insert_checkpoint_arguments(db, checkpoint_id, get_or_create_arguments(db, arguments))

      {:ok, checkpoint_id, sequence, now}
    end)
  end

  def get_latest_checkpoint(db, step_id) do
    query_one(
      db,
      """
      SELECT c.id, c.execution_id, c.sequence, c.created_at
      FROM checkpoints AS c
      INNER JOIN attempts AS a ON a.execution_id = c.execution_id
      WHERE a.step_id = ?1 AND a.type = 0
      ORDER BY a.sequence DESC, c.sequence DESC
      LIMIT 1
      """,
      {step_id}
    )
  end

  def get_checkpoint_arguments(db, checkpoint_id) do
    case query(
           db,
           """
           SELECT reference_id, value_id, blob_id
           FROM checkpoint_arguments
           WHERE checkpoint_id = ?1
           ORDER BY position
           """,
           {checkpoint_id}
         ) do
      {:ok, rows} ->
        {:ok, resolve_arguments(db, rows)}
    end
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

  def record_result(db, execution_id, result, reference_id) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {type, error_id, reference_id, value_id, blob_id} =
        case {result, reference_id} do
          {{:error, message, _}, reference_id} ->
            {:ok, error_id} = get_or_create_error(db, message)
            {0, error_id, reference_id, nil, nil}

          {:reference, reference_id} when not is_nil(reference_id) ->
            {1, nil, reference_id, nil, nil}

          {{:raw, format, value}, nil} ->
            {:ok, value_id} = get_or_create_value(db, format, value)
            {2, nil, nil, value_id, nil}

          {{:blob, format, key, metadata}, nil} ->
            {:ok, blob_id} = get_or_create_blob(db, format, key, metadata)
            {3, nil, nil, nil, blob_id}

          {:abandoned, reference_id} ->
            {4, nil, reference_id, nil, nil}

          {:cancelled, reference_id} ->
            {5, nil, reference_id, nil, nil}

          {:deferred, reference_id} ->
            {6, nil, reference_id, nil, nil}
        end

      case insert_result(db, execution_id, type, error_id, reference_id, value_id, blob_id, now) do
        {:ok, _} ->
          {:ok, now}

        {:error, "UNIQUE constraint failed: " <> _field} ->
          {:error, :already_recorded}
      end
    end)
  end

  def has_result?(db, execution_id) do
    case query_one(db, "SELECT COUNT(*) FROM results WHERE execution_id = ?1", {execution_id}) do
      {:ok, {0}} -> {:ok, false}
      {:ok, {1}} -> {:ok, true}
    end
  end

  def get_result(db, execution_id) do
    case query_one(
           db,
           """
           SELECT type, error_id, reference_id, value_id, blob_id, created_at
           FROM results
           WHERE execution_id = ?1
           """,
           {execution_id}
         ) do
      {:ok, {type, error_id, reference_id, value_id, blob_id, created_at}} ->
        {result, reference_id} =
          case {type, error_id, reference_id, value_id, blob_id} do
            {0, error_id, reference_id, nil, nil} ->
              case get_error_by_id(db, error_id) do
                {:ok, {message}} ->
                  {{:error, message, nil}, reference_id}
              end

            {1, nil, reference_id, nil, nil} ->
              {:reference, reference_id}

            {2, nil, nil, value_id, nil} ->
              case get_value_by_id(db, value_id) do
                {:ok, {format, value}} ->
                  {{:raw, format, value}, nil}
              end

            {3, nil, nil, nil, blob_id} ->
              case get_blob_by_id(db, blob_id) do
                {:ok, {format, key, encoded_metadata}} ->
                  metadata = decode_metadata(encoded_metadata)
                  {{:blob, format, key, metadata}, nil}
              end

            {4, nil, reference_id, nil, nil} ->
              {:abandoned, reference_id}

            {5, nil, reference_id, nil, nil} ->
              {:cancelled, reference_id}

            {6, nil, reference_id, nil, nil} ->
              {:deferred, reference_id}
          end

        {:ok, {result, reference_id, created_at}}

      {:ok, nil} ->
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
        run.external_id,
        s.repository,
        s.target,
        s.defer_key,
        e.execute_after,
        e.created_at
      FROM executions AS e
      INNER JOIN attempts AS at ON at.execution_id = e.id
      INNER JOIN steps AS s ON s.id = at.step_id
      INNER JOIN runs AS run ON run.id = s.run_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE at.type = 0 AND a.created_at IS NULL AND r.created_at IS NULL
      ORDER BY e.execute_after, e.created_at, s.priority DESC
      """
    )
  end

  def get_repository_executions(db, repository) do
    query(
      db,
      """
      SELECT
        e.id,
        s.target,
        r.external_id,
        s.external_id,
        at.sequence,
        e.execute_after,
        e.created_at,
        a.created_at
      FROM executions AS e
      INNER JOIN attempts AS at ON at.execution_id = e.id
      INNER JOIN steps AS s ON s.id = at.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS re ON re.execution_id = e.id
      WHERE at.type = 0 AND s.repository = ?1 AND re.created_at IS NULL
      """,
      {repository}
    )
  end

  def get_pending_assignments(db) do
    query(
      db,
      """
      SELECT a.execution_id
      FROM assignments AS a
      LEFT JOIN results AS r ON r.execution_id = a.execution_id
      WHERE r.created_at IS NULL
      """
    )
  end

  def get_run_executions(db, run_id) do
    query(
      db,
      """
      SELECT at.execution_id, s.repository, a.created_at, r.created_at
      FROM attempts AS at
      INNER JOIN steps AS s ON s.id = at.step_id
      LEFT JOIN assignments AS a ON a.execution_id = at.execution_id
      LEFT JOIN results AS r ON r.execution_id = at.execution_id
      WHERE at.type = 0 AND s.run_id = ?1
      """,
      {run_id}
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
               0 -> :workflow
               1 -> :task
               2 -> :sensor
             end

           {target, %{type: type, parameters: parameters}}
         end)}
      end)

    {:ok, targets}
  end

  def get_target_runs(db, repository, target, limit \\ 50) do
    query(
      db,
      """
      SELECT DISTINCT r.external_id, r.created_at
      FROM runs as r
      INNER JOIN steps AS s ON s.run_id = r.id
      WHERE s.repository = ?1
        AND s.target = ?2
        AND s.type = 0
      ORDER BY r.created_at DESC
      LIMIT ?3
      """,
      {repository, target, limit}
    )
  end

  def get_run_by_id(db, id) do
    query_one(
      db,
      """
      SELECT id, external_id, parent_id, idempotency_key, recurrent, created_at
      FROM runs
      WHERE id = ?1
      """,
      {id},
      Models.Run
    )
  end

  def get_run_by_external_id(db, external_id) do
    query_one(
      db,
      """
      SELECT id, external_id, parent_id, idempotency_key, recurrent, created_at
      FROM runs
      WHERE external_id = ?1
      """,
      {external_id},
      Models.Run
    )
  end

  def get_run_by_execution(db, execution_id) do
    query_one(
      db,
      """
      SELECT r.external_id, s.external_id, a.sequence, s.repository, s.target
      FROM attempts AS a
      INNER JOIN steps AS s ON s.id = a.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE a.execution_id = ?1 AND a.type = 0
      """,
      {execution_id}
    )
  end

  def get_external_run_id_for_execution(db, execution_id) do
    query_one(
      db,
      """
      SELECT r.external_id
      FROM attempts AS a
      INNER JOIN steps AS s ON s.id = a.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE a.execution_id = ?1 AND a.type = 0
      """,
      {execution_id}
    )
  end

  def get_run_steps(db, run_id) do
    query(
      db,
      """
      SELECT id, external_id, type, repository, target, memo_key, created_at
      FROM steps
      WHERE run_id = ?1
      """,
      {run_id}
    )
  end

  def get_step_attempts(db, step_id) do
    query(
      db,
      """
      SELECT e.id, at.sequence, at.type, e.execute_after, e.created_at, a.session_id, a.created_at
      FROM executions AS e
      INNER JOIN attempts AS at ON at.execution_id = e.id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      WHERE at.step_id = ?1
      """,
      {step_id}
    )
  end

  def get_step_arguments(db, step_id) do
    case query(
           db,
           """
           SELECT reference_id, value_id, blob_id
           FROM arguments
           WHERE step_id = ?1
           ORDER BY position
           """,
           {step_id}
         ) do
      {:ok, rows} ->
        {:ok, resolve_arguments(db, rows)}
    end
  end

  def get_execution_children(db, execution_id) do
    query(
      db,
      """
      SELECT r.external_id, s.external_id, c.child_id, s.repository, s.target, c.created_at
      FROM children AS c
      INNER JOIN steps AS s ON s.id = c.child_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE c.parent_id = ?1
      """,
      {execution_id}
    )
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

  defp find_memoised_execution(db, run_id, memo_key) do
    case query(
           db,
           """
           SELECT s.id, s.external_id, a.execution_id, a.sequence, a.type, a.created_at
           FROM steps AS s
           INNER JOIN attempts AS a ON a.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = a.execution_id
           WHERE s.run_id = ?1 AND s.memo_key = ?2 AND a.type = 0 AND (r.type IS NULL OR r.type IN (1, 2, 3))
           ORDER BY a.created_at DESC
           LIMIT 1
           """,
           {run_id, memo_key}
         ) do
      {:ok, [row]} ->
        {:ok, row}

      {:ok, []} ->
        {:ok, nil}
    end
  end

  defp find_cached_execution(db, cache_key) do
    case query(
           db,
           """
           SELECT a.execution_id
           FROM steps AS s
           INNER JOIN attempts AS a ON a.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = a.execution_id
           WHERE s.cache_key = ?1 AND a.type = 0 AND (r.type IS NULL OR r.type IN (1, 2, 3))
           ORDER BY a.created_at DESC
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

  defp insert_run(db, parent_id, idempotency_key, recurrent, created_at) do
    case generate_external_id(db, :runs, 2, "R") do
      {:ok, external_id} ->
        case insert_one(db, :runs, %{
               external_id: external_id,
               parent_id: parent_id,
               idempotency_key: idempotency_key,
               recurrent: if(recurrent, do: 1, else: 0),
               created_at: created_at
             }) do
          {:ok, run_id} ->
            {:ok, run_id, external_id}
        end
    end
  end

  defp insert_step(
         db,
         run_id,
         type,
         repository,
         target,
         priority,
         cache_key,
         defer_key,
         memo_key,
         retry_count,
         retry_delay_min,
         retry_delay_max,
         now
       ) do
    case generate_external_id(db, :steps, 3, "S") do
      {:ok, external_id} ->
        case insert_one(db, :steps, %{
               external_id: external_id,
               run_id: run_id,
               type: type,
               repository: repository,
               target: target,
               priority: priority,
               cache_key: cache_key,
               defer_key: defer_key,
               memo_key: memo_key,
               retry_count: retry_count,
               retry_delay_min: retry_delay_min,
               retry_delay_max: retry_delay_max,
               created_at: now
             }) do
          {:ok, step_id} ->
            {:ok, step_id, external_id}
        end
    end
  end

  defp insert_arguments(db, step_id, arguments) do
    case insert_many(
           db,
           :arguments,
           {:step_id, :position, :reference_id, :value_id, :blob_id},
           Enum.map(Enum.with_index(arguments), fn {{reference_id, value_id, blob_id}, index} ->
             {step_id, index, reference_id, value_id, blob_id}
           end)
         ) do
      {:ok, _} -> :ok
    end
  end

  defp get_or_create_arguments(db, arguments) do
    Enum.map(arguments, fn
      {:reference, execution_id} ->
        {execution_id, nil, nil}

      {:raw, format, value} ->
        {:ok, value_id} = get_or_create_value(db, format, value)
        {nil, value_id, nil}

      {:blob, format, key, metadata} ->
        {:ok, blob_id} = get_or_create_blob(db, format, key, metadata)
        {nil, nil, blob_id}
    end)
  end

  defp resolve_arguments(db, arguments) do
    Enum.map(arguments, fn
      {execution_id, nil, nil} ->
        {:reference, execution_id}

      {nil, value_id, nil} ->
        case get_value_by_id(db, value_id) do
          {:ok, {format, value}} -> {:raw, format, value}
        end

      {nil, nil, blob_id} ->
        case get_blob_by_id(db, blob_id) do
          {:ok, {format, key, encoded_metadata}} ->
            metadata = decode_metadata(encoded_metadata)
            {:blob, format, key, metadata}
        end
    end)
  end

  defp get_next_attempt_sequence(db, step_id) do
    case query(
           db,
           """
           SELECT MAX(sequence)
           FROM attempts
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

  defp insert_execution(db, execute_after, created_at) do
    insert_one(db, :executions, %{
      execute_after: execute_after,
      created_at: created_at
    })
  end

  defp insert_attempt(db, step_id, sequence, execution_id, type, created_at) do
    insert_one(db, :attempts, %{
      step_id: step_id,
      sequence: sequence,
      execution_id: execution_id,
      type: type,
      created_at: created_at
    })
  end

  defp insert_child(db, parent_id, child_id, created_at) do
    insert_one(
      db,
      :children,
      %{
        parent_id: parent_id,
        child_id: child_id,
        created_at: created_at
      },
      on_conflict: "DO NOTHING"
    )
  end

  defp insert_checkpoint(db, execution_id, sequence, created_at) do
    insert_one(db, :checkpoints, %{
      execution_id: execution_id,
      sequence: sequence,
      created_at: created_at
    })
  end

  defp insert_checkpoint_arguments(db, checkpoint_id, arguments) do
    insert_many(
      db,
      :checkpoint_arguments,
      {:checkpoint_id, :position, :reference_id, :value_id, :blob_id},
      Enum.map(Enum.with_index(arguments), fn {{reference_id, value_id, blob_id}, position} ->
        {checkpoint_id, position, reference_id, value_id, blob_id}
      end)
    )
  end

  defp get_error_by_id(db, error_id) do
    query_one!(db, "SELECT message FROM errors WHERE id = ?1", {error_id})
  end

  defp get_value_by_id(db, value_id) do
    query_one!(db, "SELECT format, value FROM `values` WHERE id = ?1", {value_id})
  end

  defp get_blob_by_id(db, blob_id) do
    query_one!(db, "SELECT format, key, metadata FROM blobs WHERE id = ?1", {blob_id})
  end

  defp get_or_create_value(db, format, value) do
    case query_one(
           db,
           "SELECT id FROM `values` WHERE format = ?1 AND value = ?2",
           {format, value}
         ) do
      {:ok, {id}} -> {:ok, id}
      {:ok, nil} -> insert_value(db, format, value)
    end
  end

  defp insert_value(db, format, value) do
    insert_one(db, :values, %{
      format: format,
      value: value
    })
  end

  defp encode_metadata(metadata) do
    # TODO: better encoding?
    metadata
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{Jason.encode!(value)}" end)
  end

  defp decode_metadata(encoded) do
    encoded
    |> String.split("\n")
    |> Enum.map(&String.split(&1, "=", parts: 2))
    |> Map.new(fn [key, value] -> {key, Jason.decode!(value)} end)
  end

  defp get_or_create_blob(db, format, key, metadata) do
    encoded_metadata = encode_metadata(metadata)

    case query_one(
           db,
           "SELECT id FROM blobs WHERE format = ?1 AND key = ?2 AND metadata = ?3",
           {format, key, encoded_metadata}
         ) do
      {:ok, {id}} -> {:ok, id}
      {:ok, nil} -> insert_blob(db, format, key, encoded_metadata)
    end
  end

  defp insert_blob(db, format, key, encoded_metadata) do
    insert_one(db, :blobs, %{
      format: format,
      key: key,
      metadata: encoded_metadata
    })
  end

  defp get_or_create_error(db, message) do
    # TODO: other fields
    case query_one(
           db,
           "SELECT id FROM errors WHERE message = ?1",
           {message}
         ) do
      {:ok, {id}} -> {:ok, id}
      {:ok, nil} -> insert_error(db, message)
    end
  end

  defp insert_error(db, message) do
    insert_one(db, :errors, %{
      message: message
    })
  end

  defp insert_result(
         db,
         execution_id,
         type,
         error_id,
         reference_id,
         value_id,
         blob_id,
         created_at
       ) do
    insert_one(db, :results, %{
      execution_id: execution_id,
      type: type,
      error_id: error_id,
      reference_id: reference_id,
      value_id: value_id,
      blob_id: blob_id,
      created_at: created_at
    })
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

    try do
      fun.()
    rescue
      e ->
        :ok = Sqlite3.execute(db, "ROLLBACK")
        reraise e, __STACKTRACE__
    else
      result ->
        :ok = Sqlite3.execute(db, "COMMIT")
        result
    end
  end

  defp with_snapshot(db, fun) do
    name = "s#{:erlang.unique_integer([:positive])}"
    :ok = Sqlite3.execute(db, "SAVEPOINT #{name}")

    try do
      fun.()
    rescue
      e ->
        :ok = Sqlite3.execute(db, "ROLLBACK TO #{name}")
        reraise e, __STACKTRACE__
    else
      {:ok, result} ->
        :ok = Sqlite3.execute(db, "RELEASE #{name}")
        {:ok, result}

      {:error, reason} ->
        :ok = Sqlite3.execute(db, "ROLLBACK TO #{name}")
        {:error, reason}
    end
  end

  defp insert_one(db, table, values, opts \\ nil) do
    {fields, values} = Enum.unzip(values)

    case insert_many(db, table, List.to_tuple(fields), [List.to_tuple(values)], opts) do
      {:ok, [id]} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_many(db, table, fields, values, opts \\ nil) do
    if Enum.any?(values) do
      {fields, indexes} =
        fields
        |> Tuple.to_list()
        |> Enum.with_index(1)
        |> Enum.unzip()

      fields = Enum.map_join(fields, ", ", &"`#{&1}`")
      placeholders = Enum.map_join(indexes, ", ", &"?#{&1}")

      sql_parts = [
        "INSERT INTO `#{table}` (#{fields})",
        "VALUES (#{placeholders})",
        if(opts[:on_conflict], do: "ON CONFLICT #{opts[:on_conflict]}")
      ]

      sql = sql_parts |> Enum.reject(&is_nil/1) |> Enum.join(" ")

      with_prepare(db, sql, fn statement ->
        with_snapshot(db, fn ->
          Enum.reduce_while(values, {:ok, []}, fn row, {:ok, ids} ->
            :ok = Sqlite3.bind(db, statement, Tuple.to_list(row))

            case Sqlite3.step(db, statement) do
              :done ->
                {:ok, changes} = Sqlite3.changes(db)

                {:ok, id} =
                  case changes do
                    0 -> {:ok, nil}
                    1 -> Sqlite3.last_insert_rowid(db)
                  end

                {:cont, {:ok, ids ++ [id]}}

              {:error, reason} ->
                {:halt, {:error, reason}}
            end
          end)
        end)
      end)
    else
      {:ok, []}
    end
  end

  defp build(row, model, columns) do
    if model do
      prepare =
        if function_exported?(model, :prepare, 1),
          do: &model.prepare/1,
          else: &Function.identity/1

      columns
      |> Enum.map(&String.to_existing_atom/1)
      |> Enum.zip(row)
      |> prepare.()
      |> then(&struct(model, &1))
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

  defp query_one!(db, sql, args, model \\ nil) do
    case query(db, sql, args, model) do
      {:ok, [row]} ->
        {:ok, row}
    end
  end
end

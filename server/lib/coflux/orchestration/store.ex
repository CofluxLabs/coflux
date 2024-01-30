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

      {:ok, step_id, external_step_id, execution_id, attempt, now, false, result, child_added} =
        do_schedule_step(db, run_id, parent_id, repository, target, arguments, true, now, opts)

      {:ok, run_id, external_run_id, step_id, external_step_id, execution_id, attempt, result,
       now, child_added}
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
        parent_id,
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
      INNER JOIN executions AS e ON e.step_id = s.id
      WHERE e.id = ?1
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

    {step_id, external_step_id, execution_id, attempt, now, memoised, result} =
      case memoised_execution do
        {step_id, external_step_id, execution_id, attempt, now} ->
          {step_id, external_step_id, execution_id, attempt, now, true, false}

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
              if(!is_initial, do: parent_id),
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

          arguments
          |> Enum.with_index()
          |> Enum.each(fn {value, position} ->
            {:ok, value_id} = get_or_create_value(db, value)
            {:ok, _} = insert_step_argument(db, step_id, position, value_id)
          end)

          attempt = 1

          {:ok, execution_id} =
            insert_execution(db, step_id, attempt, execute_after, now)

          result =
            if cached_execution_id do
              # TODO: delay if execute_after is set?
              {:ok, _} = insert_result(db, execution_id, 5, nil, nil, cached_execution_id, now)
              {:cached, cached_execution_id}
            end

          {step_id, external_step_id, execution_id, attempt, now, false, result}
      end

    child_added =
      if parent_id do
        {:ok, id} = insert_child(db, parent_id, step_id, now)
        !is_nil(id)
      else
        false
      end

    {:ok, step_id, external_step_id, execution_id, attempt, now, memoised, result, child_added}
  end

  def rerun_step(db, step_id, execute_after \\ nil) do
    with_transaction(db, fn ->
      now = current_timestamp()
      # TODO: cancel pending executions for step?
      {:ok, attempt} = get_next_execution_attempt(db, step_id)
      {:ok, execution_id} = insert_execution(db, step_id, attempt, execute_after, now)
      {:ok, execution_id, attempt, now}
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

      arguments
      |> Enum.with_index()
      |> Enum.each(fn {value, position} ->
        {:ok, value_id} = get_or_create_value(db, value)
        {:ok, _} = insert_checkpoint_argument(db, checkpoint_id, position, value_id)
      end)

      {:ok, checkpoint_id, sequence, now}
    end)
  end

  def get_latest_checkpoint(db, step_id) do
    query_one(
      db,
      """
      SELECT c.id, c.execution_id, c.sequence, c.created_at
      FROM checkpoints AS c
      INNER JOIN executions AS e ON e.id = c.execution_id
      WHERE e.step_id = ?1
      ORDER BY e.attempt DESC, c.sequence DESC
      LIMIT 1
      """,
      {step_id}
    )
  end

  def get_checkpoint_arguments(db, checkpoint_id, load_metadata \\ false) do
    case query(
           db,
           """
           SELECT value_id
           FROM checkpoint_arguments
           WHERE checkpoint_id = ?1
           ORDER BY position
           """,
           {checkpoint_id}
         ) do
      {:ok, rows} ->
        values =
          Enum.map(rows, fn {value_id} ->
            case get_value_by_id(db, value_id, load_metadata) do
              {:ok, value} -> value
            end
          end)

        {:ok, values}
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

  def record_result(db, execution_id, result) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {type, error_id, value_id, successor_id} =
        case result do
          {:error, type, message, frames, retry_id} ->
            {:ok, error_id} = get_or_create_error(db, type, message, frames)
            {0, error_id, nil, retry_id}

          {:value, value} ->
            {:ok, value_id} = get_or_create_value(db, value)
            {1, nil, value_id, nil}

          {:abandoned, retry_id} ->
            {2, nil, nil, retry_id}

          :cancelled ->
            {3, nil, nil, nil}

          {:deferred, defer_id} ->
            {4, nil, nil, defer_id}
        end

      case insert_result(db, execution_id, type, error_id, value_id, successor_id, now) do
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

  def get_result(db, execution_id, load_metadata \\ false) do
    case query_one(
           db,
           """
           SELECT type, error_id, value_id, successor_id, created_at
           FROM results
           WHERE execution_id = ?1
           """,
           {execution_id}
         ) do
      {:ok, {type, error_id, value_id, successor_id, created_at}} ->
        result =
          case {type, error_id, value_id, successor_id} do
            {0, error_id, nil, retry_id} ->
              case get_error_by_id(db, error_id) do
                {:ok, {type, message, frames}} ->
                  {:error, type, message, frames, retry_id}
              end

            {1, nil, value_id, nil} ->
              case get_value_by_id(db, value_id, load_metadata) do
                {:ok, value} -> {:value, value}
              end

            {2, nil, nil, retry_id} ->
              {:abandoned, retry_id}

            {3, nil, nil, nil} ->
              :cancelled

            {4, nil, nil, defer_id} ->
              {:deferred, defer_id}

            {5, nil, nil, cached_id} ->
              {:cached, cached_id}
          end

        {:ok, {result, created_at}}

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
      INNER JOIN steps AS s ON s.id = e.step_id
      INNER JOIN runs AS run ON run.id = s.run_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE a.created_at IS NULL AND r.created_at IS NULL
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
        e.attempt,
        e.execute_after,
        e.created_at,
        a.created_at
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS re ON re.execution_id = e.id
      WHERE s.repository = ?1 AND re.created_at IS NULL
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
      SELECT e.id, s.repository, a.created_at, r.created_at
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE s.run_id = ?1
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
      WHERE s.repository = ?1 AND s.target = ?2
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
      SELECT r.external_id, s.external_id, e.attempt, s.repository, s.target
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE e.id = ?1
      """,
      {execution_id}
    )
  end

  def get_external_run_id_for_execution(db, execution_id) do
    query_one(
      db,
      """
      SELECT r.external_id
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      INNER JOIN runs AS r ON r.id = s.run_id
      WHERE e.id = ?1
      """,
      {execution_id}
    )
  end

  def get_run_steps(db, run_id) do
    query(
      db,
      """
      SELECT id, external_id, parent_id, repository, target, memo_key, created_at
      FROM steps
      WHERE run_id = ?1
      """,
      {run_id}
    )
  end

  def get_step_executions(db, step_id) do
    query(
      db,
      """
      SELECT e.id, e.attempt, e.execute_after, e.created_at, a.session_id, a.created_at
      FROM executions AS e
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      WHERE e.step_id = ?1
      """,
      {step_id}
    )
  end

  def get_step_arguments(db, step_id, load_metadata \\ false) do
    case query(
           db,
           """
           SELECT value_id
           FROM step_arguments
           WHERE step_id = ?1
           ORDER BY position
           """,
           {step_id}
         ) do
      {:ok, rows} ->
        values =
          Enum.map(rows, fn {value_id} ->
            case get_value_by_id(db, value_id, load_metadata) do
              {:ok, value} -> value
            end
          end)

        {:ok, values}
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
           SELECT s.id, s.external_id, e.id, e.attempt, e.created_at
           FROM steps AS s
           INNER JOIN executions AS e ON e.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE s.run_id = ?1 AND s.memo_key = ?2 AND (r.type IS NULL OR r.type = 1)
           ORDER BY e.created_at DESC
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
           SELECT e.id
           FROM steps AS s
           INNER JOIN executions AS e ON e.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE s.cache_key = ?1 AND (r.type IS NULL OR r.type = 1)
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
         parent_id,
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
               parent_id: parent_id,
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

  defp insert_step_argument(db, step_id, position, value_id) do
    insert_one(db, :step_arguments, %{
      step_id: step_id,
      position: position,
      value_id: value_id
    })
  end

  defp get_next_execution_attempt(db, step_id) do
    case query(
           db,
           """
           SELECT MAX(attempt)
           FROM executions
           WHERE step_id = ?1
           """,
           {step_id}
         ) do
      {:ok, [{nil}]} ->
        {:ok, 1}

      {:ok, [{last_attempt}]} ->
        {:ok, last_attempt + 1}
    end
  end

  defp insert_execution(db, step_id, attempt, execute_after, created_at) do
    insert_one(db, :executions, %{
      step_id: step_id,
      attempt: attempt,
      execute_after: execute_after,
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

  defp insert_checkpoint_argument(db, checkpoint_id, position, value_id) do
    insert_one(db, :checkpoint_arguments, %{
      checkpoint_id: checkpoint_id,
      position: position,
      value_id: value_id
    })
  end

  defp get_error_by_id(db, error_id) do
    {:ok, {type, message}} =
      query_one!(db, "SELECT type, message FROM errors WHERE id = ?1", {error_id})

    {:ok, frames} =
      query(
        db,
        "SELECT file, line, name, code FROM error_frames WHERE error_id = ?1 ORDER BY depth",
        {error_id}
      )

    {:ok, {type, message, frames}}
  end

  defp get_value_by_id(db, value_id, load_metadata) do
    case query_one!(
           db,
           "SELECT format, content, blob_key FROM values_ WHERE id = ?1",
           {value_id}
         ) do
      {:ok, {format, content, blob_key}} ->
        references =
          case query(
                 db,
                 "SELECT number, reference_id FROM value_references WHERE value_id = ?1",
                 {value_id}
               ) do
            {:ok, rows} -> Map.new(rows)
          end

        metadata =
          if load_metadata do
            case query(
                   db,
                   "SELECT key, value FROM value_metadata WHERE value_id = ?1",
                   {value_id}
                 ) do
              {:ok, rows} ->
                Map.new(rows, fn {k, v} -> {k, Jason.decode!(v)} end)
            end
          end

        value =
          case {content, blob_key} do
            {content, nil} ->
              {:raw, format, content, references, metadata}

            {nil, blob_key} ->
              {:blob, format, blob_key, references, metadata}
          end

        {:ok, value}
    end
  end

  defp hash_value(format, content, blob_key, metadata, references) do
    metadata_parts =
      metadata
      |> Enum.sort()
      |> Enum.flat_map(fn {k, v} -> [k, Jason.encode!(v)] end)

    references_parts =
      references
      |> Enum.sort()
      |> Enum.flat_map(fn {k, v} -> [Integer.to_string(k), Integer.to_string(v)] end)

    parts = [format, content || 0, blob_key || 0, references_parts, metadata_parts]
    :crypto.hash(:sha256, Enum.intersperse(parts, 0))
  end

  defp get_or_create_value(db, value) do
    {format, content, blob_key, references, metadata} =
      case value do
        {:raw, format, content, references, metadata} ->
          {format, content, nil, references, metadata}

        {:blob, format, blob_key, references, metadata} ->
          {format, nil, blob_key, references, metadata}
      end

    hash = hash_value(format, content, blob_key, metadata, references)

    # TODO: don't assume hash is unique?
    case query_one(db, "SELECT id FROM values_ WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, value_id} =
          insert_one(db, :values_, %{
            hash: hash,
            format: format,
            content: content,
            blob_key: blob_key
          })

        {:ok, _} =
          insert_many(
            db,
            :value_references,
            {:value_id, :number, :reference_id},
            Enum.map(references, fn {number, reference_id} ->
              {value_id, number, reference_id}
            end)
          )

        {:ok, _} =
          insert_many(
            db,
            :value_metadata,
            {:value_id, :key, :value},
            Enum.map(metadata, fn {k, v} ->
              {value_id, k, Jason.encode!(v)}
            end)
          )

        {:ok, value_id}
    end
  end

  defp hash_error(type, message, frames) do
    frame_parts =
      Enum.flat_map(frames, fn {file, line, name, code} ->
        [file, Integer.to_string(line), name || 0, code || 0]
      end)

    parts = Enum.concat([type, message], frame_parts)
    :crypto.hash(:sha256, Enum.intersperse(parts, 0))
  end

  defp get_or_create_error(db, type, message, frames) do
    hash = hash_error(type, message, frames)

    # TODO: don't assume hash is unique?
    case query_one(db, "SELECT id FROM errors WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, error_id} =
          insert_one(db, :errors, %{
            hash: hash,
            type: type,
            message: message
          })

        {:ok, _} =
          insert_many(
            db,
            :error_frames,
            {:error_id, :depth, :file, :line, :name, :code},
            frames
            |> Enum.with_index()
            |> Enum.map(fn {{file, line, name, code}, index} ->
              {error_id, index, file, line, name, code}
            end)
          )

        {:ok, error_id}
    end
  end

  defp insert_result(
         db,
         execution_id,
         type,
         error_id,
         value_id,
         successor_id,
         created_at
       ) do
    insert_one(db, :results, %{
      execution_id: execution_id,
      type: type,
      error_id: error_id,
      value_id: value_id,
      successor_id: successor_id,
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

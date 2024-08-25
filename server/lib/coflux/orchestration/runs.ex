defmodule Coflux.Orchestration.Runs do
  alias Coflux.Orchestration.{Models, Results, Sessions}

  import Coflux.Store

  def schedule_run(db, repository, target, arguments, environment_id, opts \\ []) do
    idempotency_key = Keyword.get(opts, :idempotency_key)
    parent_id = Keyword.get(opts, :parent_id)
    recurrent = Keyword.get(opts, :recurrent)
    now = current_timestamp()

    with_transaction(db, fn ->
      {:ok, run_id, external_run_id} = insert_run(db, parent_id, idempotency_key, recurrent, now)

      {:ok, step_id, external_step_id, execution_id, attempt, now, false, result, child_added} =
        schedule_step(
          db,
          run_id,
          parent_id,
          repository,
          target,
          arguments,
          true,
          environment_id,
          now,
          opts
        )

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
        wait_for,
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
        s.wait_for,
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

  def get_environment_for_execution(db, execution_id) do
    case query_one!(
           db,
           "SELECT environment_id FROM executions WHERE id = ?1",
           {execution_id}
         ) do
      {:ok, {environment_id}} -> {:ok, environment_id}
    end
  end

  def schedule_task(
        db,
        run_id,
        parent_id,
        repository,
        target,
        arguments,
        environment_id,
        opts \\ []
      ) do
    now = current_timestamp()

    with_transaction(db, fn ->
      schedule_step(
        db,
        run_id,
        parent_id,
        repository,
        target,
        arguments,
        false,
        environment_id,
        now,
        opts
      )
    end)
  end

  defp schedule_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         arguments,
         is_initial,
         environment_id,
         now,
         opts
       ) do
    priority = Keyword.get(opts, :priority, 0)
    execute_after = Keyword.get(opts, :execute_after)
    wait_for = Keyword.get(opts, :wait_for)
    cache_key = Keyword.get(opts, :cache_key)
    cache_max_age = Keyword.get(opts, :cache_max_age)
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
              recorded_after = if cache_max_age, do: now - cache_max_age * 1000, else: 0

              {:ok, environment_ids} = Sessions.get_cache_environment_ids(db, environment_id)

              case find_cached_execution(db, environment_ids, cache_key, recorded_after) do
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
              wait_for,
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
            {:ok, value_id} = Results.get_or_create_value(db, value)
            {:ok, _} = insert_step_argument(db, step_id, position, value_id)
          end)

          attempt = 1

          {:ok, execution_id} =
            insert_execution(db, step_id, attempt, environment_id, execute_after, now)

          result =
            if cached_execution_id do
              # TODO: delay if execute_after is set?
              {:ok, _} =
                Results.insert_result(db, execution_id, 5, nil, nil, cached_execution_id, now)

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

  def rerun_step(db, step_id, environment_id, execute_after) do
    with_transaction(db, fn ->
      now = current_timestamp()
      # TODO: cancel pending executions for step?
      {:ok, attempt} = get_next_execution_attempt(db, step_id)

      {:ok, execution_id} =
        insert_execution(db, step_id, attempt, environment_id, execute_after, now)

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

  def record_hearbeats(db, executions) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {:ok, _} =
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

  def record_result_dependency(db, execution_id, dependency_id) do
    with_transaction(db, fn ->
      insert_one(
        db,
        :result_dependencies,
        %{
          execution_id: execution_id,
          dependency_id: dependency_id,
          created_at: current_timestamp()
        },
        on_conflict: "DO NOTHING"
      )
    end)
  end

  def record_asset_dependency(db, execution_id, asset_id) do
    with_transaction(db, fn ->
      insert_one(
        db,
        :asset_dependencies,
        %{
          execution_id: execution_id,
          asset_id: asset_id,
          created_at: current_timestamp()
        },
        on_conflict: "DO NOTHING"
      )
    end)
  end

  def get_unassigned_executions(db) do
    query(
      db,
      """
      SELECT
        e.id AS execution_id,
        s.id AS step_id,
        s.run_id,
        run.external_id AS run_external_id,
        run.recurrent AS run_recurrent,
        s.repository,
        s.target,
        s.wait_for,
        s.defer_key,
        s.parent_id,
        e.environment_id,
        e.execute_after,
        e.created_at
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      INNER JOIN runs AS run ON run.id = s.run_id
      LEFT JOIN assignments AS a ON a.execution_id = e.id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE a.created_at IS NULL AND r.created_at IS NULL
      ORDER BY e.execute_after, e.created_at, s.priority DESC
      """,
      {},
      Models.UnassignedExecution
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

  def get_target_runs(db, repository, target, environment_id, limit \\ 50) do
    query(
      db,
      """
      SELECT DISTINCT r.external_id, r.created_at
      FROM runs as r
      INNER JOIN steps AS s ON s.run_id = r.id
      INNER JOIN executions AS e ON e.step_id == s.id
      WHERE s.repository = ?1 AND s.target = ?2 AND s.parent_id IS NULL AND e.environment_id = ?3
      ORDER BY r.created_at DESC
      LIMIT ?4
      """,
      {repository, target, environment_id, limit}
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

  def get_run_target(db, run_id) do
    query_one(
      db,
      """
      SELECT repository, target
      FROM steps
      WHERE run_id = ?1 AND parent_id IS NULL
      """,
      {run_id}
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
      SELECT e.id, e.attempt, e.environment_id, e.execute_after, e.created_at, a.session_id, a.created_at
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
            case Results.get_value_by_id(db, value_id, load_metadata) do
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

  def get_result_dependencies(db, execution_id) do
    query(
      db,
      """
      SELECT dependency_id
      FROM result_dependencies
      WHERE execution_id = ?1
      """,
      {execution_id}
    )
  end

  def get_asset_dependencies(db, execution_id) do
    query(
      db,
      """
      SELECT asset_id
      FROM asset_dependencies
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

  defp find_cached_execution(db, environment_ids, cache_key, recorded_after) do
    environment_placeholders =
      1..length(environment_ids)
      |> Enum.map_intersperse(", ", &"?#{&1}")
      |> Enum.join()

    case query(
           db,
           """
           SELECT e.id
           FROM steps AS s
           INNER JOIN executions AS e ON e.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE
             e.environment_id IN (#{environment_placeholders})
             AND s.cache_key = ?#{length(environment_ids) + 1}
             AND (r.type IS NULL OR (r.type = 1 AND r.created_at >= ?#{length(environment_ids) + 2}))
           ORDER BY e.created_at DESC
           LIMIT 1
           """,
           List.to_tuple(environment_ids)
           |> Tuple.append(cache_key)
           |> Tuple.append(recorded_after)
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

  defp encode_wait_for(indexes) do
    indexes && Enum.reduce(indexes, 0, &Bitwise.bor(&2, Bitwise.bsl(1, &1)))
  end

  defp insert_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         priority,
         wait_for,
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
               wait_for: encode_wait_for(wait_for),
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

  defp insert_execution(db, step_id, attempt, environment_id, execute_after, created_at) do
    insert_one(db, :executions, %{
      step_id: step_id,
      attempt: attempt,
      environment_id: environment_id,
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

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end

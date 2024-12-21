defmodule Coflux.Orchestration.Runs do
  alias Coflux.Orchestration.{Models, Values, TagSets, Utils}

  import Coflux.Store

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
        type,
        priority,
        wait_for,
        cache_key,
        cache_max_age,
        retry_limit,
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
        s.type,
        s.target,
        s.priority,
        s.wait_for,
        s.cache_key,
        s.cache_max_age,
        s.retry_limit,
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

  def get_environment_id_for_execution(db, execution_id) do
    case query_one!(
           db,
           "SELECT environment_id FROM executions WHERE id = ?1",
           {execution_id}
         ) do
      {:ok, {environment_id}} -> {:ok, environment_id}
    end
  end

  def get_steps_for_environment(db, environment_id) do
    case query(
           db,
           """
           WITH latest_executions AS (
             SELECT s.repository, s.target, MAX(e.created_at) AS max_created_at
             FROM executions AS e
             INNER JOIN steps AS s ON s.id = e.step_id
             WHERE e.environment_id = ?1
             GROUP BY s.repository, s.target
           )
           SELECT s.repository, s.target, s.type, r.external_id, s.external_id, e.attempt
           FROM executions AS e
           INNER JOIN steps AS s ON s.id = e.step_id
           INNER JOIN latest_executions AS le ON s.repository = le.repository AND s.target = le.target AND e.created_at = le.max_created_at
           INNER JOIN runs AS r ON r.id = s.run_id
           WHERE e.environment_id = ?1
           """,
           {environment_id}
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn {repository_name, target_name, target_type, run_external_id,
                            step_external_id, attempt} ->
           {repository_name, target_name, Utils.decode_step_type(target_type), run_external_id,
            step_external_id, attempt}
         end)}
    end
  end

  def schedule_run(
        db,
        repository,
        target,
        type,
        arguments,
        environment_id,
        cache_environment_ids,
        opts \\ []
      ) do
    idempotency_key = Keyword.get(opts, :idempotency_key)
    parent_id = Keyword.get(opts, :parent_id)
    now = current_timestamp()

    # TODO: check that 'type' is :workflow or :sensor?

    with_transaction(db, fn ->
      {:ok, run_id, external_run_id} = insert_run(db, parent_id, idempotency_key, now)

      {:ok, external_step_id, execution_id, attempt, now, false, child_added} =
        do_schedule_step(
          db,
          run_id,
          parent_id,
          repository,
          target,
          type,
          arguments,
          true,
          environment_id,
          cache_environment_ids,
          now,
          opts
        )

      {:ok, external_run_id, external_step_id, execution_id, attempt, now, child_added}
    end)
  end

  def schedule_step(
        db,
        run_id,
        parent_id,
        repository,
        target,
        type,
        arguments,
        environment_id,
        cache_environment_ids,
        opts \\ []
      ) do
    now = current_timestamp()

    with_transaction(db, fn ->
      do_schedule_step(
        db,
        run_id,
        parent_id,
        repository,
        target,
        type,
        arguments,
        false,
        environment_id,
        cache_environment_ids,
        now,
        opts
      )
    end)
  end

  defp get_argument_key_parts(parameter) do
    references =
      case parameter do
        {:raw, _data, references} -> references
        {:blob, _blob_key, _size, references} -> references
      end

    references_parts =
      [
        length(references)
        | Enum.flat_map(references, fn
            {:fragment, serialiser, blob_key, _size, metadata} ->
              Enum.concat(
                [1, serialiser, blob_key],
                Enum.flat_map(metadata, fn {key, value} -> [key, Jason.encode!(value)] end)
              )

            {:execution, execution_id} ->
              [2, Integer.to_string(execution_id)]

            {:asset, asset_id} ->
              [3, Integer.to_string(asset_id)]
          end)
      ]

    # TODO: safer data encoding? (consider order of, e.g., dicts)
    case parameter do
      {:raw, data, _references} -> Enum.concat([1, Jason.encode!(data)], references_parts)
      {:blob, blob_key, _size, _references} -> Enum.concat([2, blob_key], references_parts)
    end
  end

  defp build_key(params, arguments, namespace, version \\ nil) do
    params =
      if params == true,
        do: Enum.map(Enum.with_index(arguments), fn {_, i} -> i end),
        else: params

    parameter_parts =
      Enum.map(params, &get_argument_key_parts(Enum.at(arguments, &1)))

    data =
      [namespace, version || ""]
      |> Enum.concat(parameter_parts)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  defp do_schedule_step(
         db,
         run_id,
         parent_id,
         repository,
         target,
         type,
         arguments,
         is_initial,
         environment_id,
         cache_environment_ids,
         now,
         opts
       ) do
    priority = Keyword.get(opts, :priority, 0)
    wait_for = Keyword.get(opts, :wait_for)
    cache = Keyword.get(opts, :cache)
    defer = Keyword.get(opts, :defer)
    memo = Keyword.get(opts, :memo)
    execute_after = Keyword.get(opts, :execute_after)
    retries = Keyword.get(opts, :retries)
    requires = Keyword.get(opts, :requires) || %{}

    memo_key = if memo, do: build_key(memo, arguments, "#{repository}:#{target}")

    memoised_execution =
      if memo_key do
        case find_memoised_execution(db, run_id, cache_environment_ids, memo_key) do
          {:ok, memoised_execution} -> memoised_execution
        end
      end

    {step_id, external_step_id, execution_id, attempt, now, memo_hit} =
      case memoised_execution do
        {step_id, external_step_id, execution_id, attempt, now} ->
          {step_id, external_step_id, execution_id, attempt, now, true, false}

        nil ->
          {cache_key, cache_max_age} =
            cond do
              is_binary(cache) ->
                {cache, 0}

              cache ->
                {build_key(
                   cache.params,
                   arguments,
                   cache.namespace || "#{repository}:#{target}",
                   cache.version
                 ), cache.max_age}

              true ->
                {nil, nil}
            end

          requires_tag_set_id =
            if Enum.any?(requires) do
              case TagSets.get_or_create_tag_set_id(db, requires) do
                {:ok, tag_set_id} ->
                  tag_set_id
              end
            end

          defer_key =
            if defer,
              do: build_key(defer.params, arguments, "#{repository}:#{target}")

          # TODO: validate parent belongs to run?
          {:ok, step_id, external_step_id} =
            insert_step(
              db,
              run_id,
              if(!is_initial, do: parent_id),
              repository,
              target,
              type,
              priority,
              wait_for,
              cache_key,
              cache_max_age,
              defer_key,
              memo_key,
              if(retries, do: retries.limit, else: 0),
              if(retries, do: retries.delay_min, else: 0),
              if(retries, do: retries.delay_max, else: 0),
              requires_tag_set_id,
              now
            )

          {:ok, _} =
            insert_many(
              db,
              :step_arguments,
              {:step_id, :position, :value_id},
              arguments
              |> Enum.with_index()
              |> Enum.map(fn {value, position} ->
                {:ok, value_id} = Values.get_or_create_value(db, value)
                {step_id, position, value_id}
              end)
            )

          attempt = 1

          {:ok, execution_id} =
            insert_execution(db, step_id, attempt, environment_id, execute_after, now)

          {step_id, external_step_id, execution_id, attempt, now, false}
      end

    child_added =
      if parent_id do
        {:ok, id} = insert_child(db, parent_id, step_id, now)
        !is_nil(id)
      else
        false
      end

    {:ok, external_step_id, execution_id, attempt, now, memo_hit, child_added}
  end

  def rerun_step(db, step_id, environment_id, execute_after, dependency_ids) do
    with_transaction(db, fn ->
      now = current_timestamp()
      # TODO: cancel pending executions for step?
      {:ok, attempt} = get_next_execution_attempt(db, step_id)

      {:ok, execution_id} =
        insert_execution(db, step_id, attempt, environment_id, execute_after, now)

      {:ok, _} =
        insert_many(
          db,
          :result_dependencies,
          {:execution_id, :dependency_id, :created_at},
          Enum.map(dependency_ids, &{execution_id, &1, now})
        )

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
        s.repository,
        s.target,
        s.type,
        s.wait_for,
        s.cache_key,
        s.cache_max_age,
        s.defer_key,
        s.parent_id,
        s.requires_tag_set_id,
        s.retry_limit,
        s.retry_delay_min,
        s.retry_delay_max,
        e.environment_id,
        e.execute_after,
        e.attempt,
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

  def get_pending_executions_for_environment(db, environment_id) do
    query(
      db,
      """
      SELECT e.id, s.run_id, s.repository
      FROM executions AS e
      INNER JOIN steps AS s ON s.id = e.step_id
      LEFT JOIN results AS r ON r.execution_id = e.id
      WHERE e.environment_id = ?1 AND r.created_at IS NULL
      """,
      {environment_id}
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
      SELECT id, external_id, parent_id, idempotency_key, created_at
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
      SELECT id, external_id, parent_id, idempotency_key, created_at
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

  # TODO: use Step model?
  def get_run_steps(db, run_id) do
    case query(
           db,
           """
           SELECT id, external_id, parent_id, repository, target, type, memo_key, requires_tag_set_id, created_at
           FROM steps
           WHERE run_id = ?1
           """,
           {run_id}
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn {id, external_id, parent_id, repository, target, type, memo_key,
                            requires_tag_set_id, created_at} ->
           {id, external_id, parent_id, repository, target, Utils.decode_step_type(type),
            memo_key, requires_tag_set_id, created_at}
         end)}
    end
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

  def get_first_step_execution_id(db, step_id) do
    case query_one(
           db,
           """
           SELECT id
           FROM executions
           WHERE step_id = ?1
           ORDER BY attempt ASC
           LIMIT 1
           """,
           {step_id}
         ) do
      {:ok, {id}} -> {:ok, id}
    end
  end

  def get_step_arguments(db, step_id) do
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
            case Values.get_value_by_id(db, value_id) do
              {:ok, value} -> value
            end
          end)

        {:ok, values}
    end
  end

  def get_execution_children(db, execution_id) do
    case query(
           db,
           """
           SELECT r.external_id, s.external_id, s.repository, s.target, s.type
           FROM children AS c
           INNER JOIN steps AS s ON s.id = c.child_id
           INNER JOIN runs AS r ON r.id = s.run_id
           WHERE c.parent_id = ?1
           """,
           {execution_id}
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(rows, fn {run_external_id, step_external_id, repository, target, type} ->
           {run_external_id, step_external_id, repository, target, Utils.decode_step_type(type)}
         end)}
    end
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

  defp build_placeholders(count, offset \\ 0) do
    1..count
    |> Enum.map_intersperse(", ", &"?#{&1 + offset}")
    |> Enum.join()
  end

  # TODO: consider changed 'requires'?
  defp find_memoised_execution(db, run_id, environment_ids, memo_key) do
    case query(
           db,
           """
           SELECT s.id, s.external_id, e.id, e.attempt, e.created_at
           FROM steps AS s
           INNER JOIN executions AS e ON e.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE
             s.run_id = ?1
             AND e.environment_id IN (#{build_placeholders(length(environment_ids), 1)})
             AND s.memo_key = ?#{length(environment_ids) + 2}
             AND (r.type IS NULL OR r.type = 1)
           ORDER BY e.created_at DESC
           LIMIT 1
           """,
           List.to_tuple([run_id] ++ environment_ids ++ [memo_key])
         ) do
      {:ok, [row]} ->
        {:ok, row}

      {:ok, []} ->
        {:ok, nil}
    end
  end

  def find_cached_execution(db, environment_ids, step_id, cache_key, recorded_after) do
    case query(
           db,
           """
           SELECT e.id
           FROM steps AS s
           INNER JOIN executions AS e ON e.step_id = s.id
           LEFT JOIN results AS r ON r.execution_id = e.id
           WHERE
             e.environment_id IN (#{build_placeholders(length(environment_ids))})
             AND s.cache_key = ?#{length(environment_ids) + 1}
             AND (r.type IS NULL OR (r.type = 1 AND r.created_at >= ?#{length(environment_ids) + 2}))
             AND s.id <> ?#{length(environment_ids) + 3}
           ORDER BY e.created_at DESC
           LIMIT 1
           """,
           List.to_tuple(environment_ids ++ [cache_key, recorded_after, step_id])
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
        case insert_one(db, :runs, %{
               external_id: external_id,
               parent_id: parent_id,
               idempotency_key: idempotency_key,
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
         type,
         priority,
         wait_for,
         cache_key,
         cache_max_age,
         defer_key,
         memo_key,
         retry_limit,
         retry_delay_min,
         retry_delay_max,
         requires_tag_set_id,
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
               type: Utils.encode_step_type(type),
               priority: priority,
               wait_for: Utils.encode_params_set(wait_for || []),
               cache_key: cache_key,
               cache_max_age: cache_max_age,
               defer_key: defer_key,
               memo_key: memo_key,
               retry_limit: retry_limit,
               retry_delay_min: retry_delay_min,
               retry_delay_max: retry_delay_max,
               requires_tag_set_id: requires_tag_set_id,
               created_at: now
             }) do
          {:ok, step_id} ->
            {:ok, step_id, external_id}
        end
    end
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

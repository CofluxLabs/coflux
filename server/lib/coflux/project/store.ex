defmodule Coflux.Project.Store do
  alias Coflux.Project.Models
  alias Coflux.Repo.Projects, as: Repo

  import Ecto.Query, only: [from: 2]

  def list_tasks(project_id) do
    Repo.all(Models.Task, prefix: project_id)
  end

  def list_task_runs(project_id, task_id) do
    query = from(r in Models.Run, where: r.task_id == ^task_id)
    Repo.all(query, prefix: project_id)
  end

  def get_task(project_id, task_id) do
    Repo.get!(Models.Task, task_id, prefix: project_id)
  end

  def get_run(project_id, run_id) do
    Repo.get!(Models.Run, run_id, prefix: project_id)
  end

  def get_steps(project_id, run_id, step_ids \\ nil) do
    query = from(s in Models.Step, where: s.run_id == ^run_id)
    query = if step_ids, do: from(s in query, where: s.id in ^step_ids), else: query
    Repo.all(query, prefix: project_id)
  end

  def get_attempts(project_id, run_id) do
    query = from(a in Models.Attempt, where: a.run_id == ^run_id)
    Repo.all(query, prefix: project_id)
  end

  def get_dependencies(project_id, execution_ids) do
    query = from(d in Models.Dependency, where: d.execution_id in ^execution_ids)
    Repo.all(query, prefix: project_id)
  end

  def get_assignments(project_id, execution_ids) do
    query = from(a in Models.Assignment, where: a.execution_id in ^execution_ids)
    Repo.all(query, prefix: project_id)
  end

  def get_results(project_id, execution_ids) do
    query = from(r in Models.Result, where: r.execution_id in ^execution_ids)
    Repo.all(query, prefix: project_id)
  end

  def create_tasks(project_id, repository, version, manifest) do
    tasks =
      manifest
      |> Enum.filter(fn {_target, config} -> config.type == :task end)
      |> Enum.map(fn {target, config} ->
        %{
          repository: repository,
          version: version,
          target: target,
          parameters: config.parameters,
          created_at: DateTime.utc_now()
        }
      end)

    Repo.insert_all(Models.Task, tasks, prefix: project_id, on_conflict: :nothing)
  end

  def schedule_task(project_id, task_id, arguments, opts \\ []) do
    run_tags = Keyword.get(opts, :run_tags, [])
    task_tags = Keyword.get(opts, :step_tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :version)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    Repo.transaction(fn ->
      task = Repo.get!(Models.Task, task_id, prefix: project_id)
      now = DateTime.utc_now()

      # TODO: hash key with (some?) task details
      existing_run =
        idempotency_key &&
          Repo.get_by(Models.Run, [idempotency_key: idempotency_key], prefix: project_id)

      if existing_run do
        query =
          from(s in Models.Step, where: s.run_id == ^existing_run.id and is_nil(s.parent_attempt))

        initial_step = Repo.one!(query, prefix: project_id)

        query =
          from(e in Models.Attempt,
            where: e.run_id == ^existing_run.id and e.step_id == ^initial_step.id,
            order_by: [desc: :attempt],
            limit: 1
          )

        latest_attempt = Repo.one!(query, prefix: project_id)
        {existing_run.id, latest_attempt.execution_id}
      else
        run =
          Repo.insert!(
            %Models.Run{
              id: Base.encode32(:rand.bytes(10)),
              task_id: task_id,
              tags: run_tags,
              idempotency_key: idempotency_key,
              created_at: now
            },
            prefix: project_id
          )

        execution_id =
          schedule_step(project_id, run, task.repository, task.target, arguments,
            now: now,
            tags: task_tags,
            priority: priority,
            version: version
          )

        {run.id, execution_id}
      end
    end)
  end

  def schedule_child(project_id, from_execution_id, repository, target, arguments, opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :keyword)
    cache_key = Keyword.get(opts, :cache_key)

    Repo.transaction(fn ->
      from_attempt =
        Repo.get_by!(Models.Attempt, [execution_id: from_execution_id], prefix: project_id)

      run = Repo.get!(Models.Run, from_attempt.run_id, prefix: project_id)
      now = DateTime.utc_now()

      execution_id =
        schedule_step(project_id, run, repository, target, arguments,
          now: now,
          tags: tags,
          priority: priority,
          version: version,
          parent_step_id: from_attempt.step_id,
          parent_attempt: from_attempt.number,
          cache_key: cache_key
        )

      {run.id, execution_id}
    end)
  end

  def record_heartbeats(project_id, executions) do
    now = DateTime.utc_now()

    Repo.insert_all(
      Models.Heartbeat,
      Enum.map(executions, fn {execution_id, status} ->
        %{execution_id: execution_id, created_at: now, status: status}
      end),
      prefix: project_id
    )
  end

  def list_pending_executions(project_id) do
    now = DateTime.utc_now()

    query =
      from(e in Models.Execution,
        left_join: a in Models.Assignment,
        on: a.execution_id == e.id,
        where: e.execute_after <= ^now or is_nil(e.execute_after),
        where: is_nil(a.execution_id),
        order_by: [desc: e.priority, asc: e.created_at]
      )

    Repo.all(query, prefix: project_id)
  end

  def list_running_executions(project_id) do
    query =
      from(e in Models.Execution,
        join: a in Models.Assignment,
        on: a.execution_id == e.id,
        left_join: r in Models.Result,
        on: r.execution_id == e.id,
        left_join: h in Models.Heartbeat,
        on: h.execution_id == e.id,
        where: is_nil(r.execution_id),
        distinct: [e.id],
        order_by: [e.id, desc: h.created_at],
        select: {e, a, h}
      )

    Repo.all(query, prefix: project_id)
  end

  def abandon_execution(project_id, execution) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Repo.insert!(
        %Models.Result{
          execution_id: execution.id,
          type: 4,
          created_at: now
        },
        prefix: project_id
      )
    end)
  end

  def assign_execution(project_id, execution) do
    case Repo.insert(
           %Models.Assignment{
             execution_id: execution.id,
             created_at: DateTime.utc_now()
           },
           prefix: project_id
         ) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  def put_result(project_id, execution_id, result) do
    {type, value, extra} = parse_result(result)

    Repo.insert!(
      %Models.Result{
        execution_id: execution_id,
        type: type,
        value: value,
        extra: extra,
        created_at: DateTime.utc_now()
      },
      prefix: project_id
    )
  end

  def get_result(project_id, execution_id) do
    case Repo.get_by(Models.Result, [execution_id: execution_id], prefix: project_id) do
      nil -> nil
      result -> compose_result(result)
    end
  end

  def record_dependency(project_id, from, to) do
    Repo.insert!(
      %Models.Dependency{
        execution_id: from,
        dependency_id: to,
        created_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      prefix: project_id
    )
  end

  defp parse_result(result) do
    case result do
      {:json, value} when is_binary(value) -> {0, value, nil}
      {:blob, key} when is_binary(key) -> {1, key, nil}
      {:result, execution_id} when is_binary(execution_id) -> {2, execution_id, nil}
      {:failed, error, stacktrace} -> {3, error, stacktrace}
    end
  end

  defp compose_result(result) do
    case result.type do
      0 -> {:json, result.value}
      1 -> {:blob, result.value}
      2 -> {:result, result.value}
      3 -> {:failed, result.value, result.extra}
      4 -> nil
    end
  end

  defp parse_argument({type, value}) do
    case type do
      :json when is_binary(value) -> "json:#{value}"
      :blob when is_binary(value) -> "blob:#{value}"
      :result when is_binary(value) -> "result:#{value}"
    end
  end

  defp schedule_step(project_id, run, repository, target, arguments, opts) do
    now = Keyword.fetch!(opts, :now)
    tags = Keyword.fetch!(opts, :tags)
    priority = Keyword.fetch!(opts, :priority)
    version = Keyword.fetch!(opts, :version)
    parent_step_id = Keyword.get(opts, :parent_step_id)
    parent_attempt = Keyword.get(opts, :parent_attempt)

    cache_key = Keyword.get(opts, :cache_key)

    cached_step =
      if cache_key do
        query =
          from(
            s in Models.Step,
            where: s.cache_key == ^cache_key,
            order_by: [desc: s.created_at],
            limit: 1
          )

        Repo.one(query, prefix: project_id)
      end

    step =
      Repo.insert!(
        %Models.Step{
          run_id: run.id,
          id: Base.encode32(:rand.bytes(5)),
          parent_step_id: parent_step_id,
          parent_attempt: parent_attempt,
          repository: repository,
          target: target,
          arguments: Enum.map(arguments, &parse_argument/1),
          tags: run.tags ++ tags,
          priority: priority,
          cache_key: unless(cached_step, do: cache_key),
          cached_run_id: if(cached_step, do: cached_step.run_id),
          cached_step_id: if(cached_step, do: cached_step.id),
          created_at: now
        },
        prefix: project_id
      )

    execution_id =
      if cached_step do
        # TODO: check result and handle failed execution? (create new step? and/or reschedule?)
        query =
          from(
            a in Models.Attempt,
            where: a.run_id == ^cached_step.run_id and a.step_id == ^cached_step.id,
            order_by: [desc: a.created_at],
            limit: 1
          )

        attempt = Repo.one!(query, prefix: project_id)
        attempt.execution_id
      else
        execution =
          Repo.insert!(
            %Models.Execution{
              repository: step.repository,
              target: step.target,
              arguments: step.arguments,
              tags: step.tags,
              priority: step.priority,
              version: version,
              created_at: now
            },
            prefix: project_id
          )

        Repo.insert!(
          %Models.Attempt{
            run_id: step.run_id,
            step_id: step.id,
            number: 1,
            execution_id: execution.id,
            created_at: now
          },
          prefix: project_id
        )

        execution.id
      end

    execution_id
  end
end

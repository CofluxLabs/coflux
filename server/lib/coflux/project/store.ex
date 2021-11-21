defmodule Coflux.Project.Store do
  alias Coflux.Project.Models
  alias Coflux.Repo.Projects, as: Repo

  import Ecto.Query, only: [from: 2]
  import Coflux.Project.Utils

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

  def get_executions(project_id, run_id) do
    query = from(e in Models.Execution, where: e.run_id == ^run_id)
    Repo.all(query, prefix: project_id)
  end

  def get_dependencies(project_id, run_id) do
    query = from(d in Models.Dependency, where: d.run_id == ^run_id)
    Repo.all(query, prefix: project_id)
  end

  def get_assignments(project_id, run_id) do
    query = from(a in Models.Assignment, where: a.run_id == ^run_id)
    Repo.all(query, prefix: project_id)
  end

  def get_results(project_id, run_id) do
    query = from(r in Models.Result, where: r.run_id == ^run_id)
    Repo.all(query, prefix: project_id)
  end

  def create_tasks(project_id, repository, version, targets) do
    tasks =
      targets
      |> Enum.filter(fn {_target, config} -> config.type == :task end)
      |> Enum.map(fn {target, _} ->
        %{
          repository: repository,
          version: version,
          target: target,
          created_at: DateTime.utc_now()
        }
      end)

    Repo.insert_all(Models.Task, tasks, prefix: project_id, on_conflict: :nothing)
  end

  def schedule_task(project_id, task_id, arguments, opts \\ []) do
    run_tags = Keyword.get(opts, :run_tags, [])
    task_tags = Keyword.get(opts, :task_tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :keyword)

    Repo.transaction(fn ->
      task = Repo.get!(Models.Task, task_id, prefix: project_id)
      now = DateTime.utc_now()

      run =
        Repo.insert!(
          %Models.Run{
            id: Base.encode32(:rand.bytes(10)),
            task_id: task_id,
            tags: run_tags,
            created_at: now
          },
          prefix: project_id
        )

      schedule_step(project_id, run, task.repository, task.target, arguments,
        now: now,
        tags: task_tags,
        priority: priority,
        version: version
      )
    end)
  end

  def schedule_child(project_id, parent_id, repository, target, arguments, opts \\ []) do
    {run_id, parent_step_id, parent_attempt} = decode_execution_id(parent_id)
    tags = Keyword.get(opts, :tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :keyword)
    cache_key = Keyword.get(opts, :cache_key)

    Repo.transaction(fn ->
      run = Repo.get!(Models.Run, run_id, prefix: project_id)
      now = DateTime.utc_now()

      schedule_step(project_id, run, repository, target, arguments,
        now: now,
        tags: tags,
        priority: priority,
        version: version,
        parent_step_id: parent_step_id,
        parent_attempt: parent_attempt,
        cache_key: cache_key
      )
    end)
  end

  def record_heartbeats(project_id, execution_ids) do
    now = DateTime.utc_now()

    Repo.insert_all(
      Models.Heartbeat,
      execution_ids
      |> Enum.map(&decode_execution_id/1)
      |> Enum.map(fn {run_id, step_id, attempt} ->
        %{run_id: run_id, step_id: step_id, attempt: attempt, created_at: now}
      end),
      prefix: project_id
    )
  end

  def list_pending_executions(project_id) do
    now = DateTime.utc_now()

    query =
      from(e in Models.Execution,
        join: s in Models.Step,
        on: s.run_id == e.run_id and s.id == e.step_id,
        left_join: a in Models.Assignment,
        on: a.run_id == e.run_id and a.step_id == e.step_id and a.attempt == e.attempt,
        where: e.execute_after <= ^now or is_nil(e.execute_after),
        where: is_nil(a.attempt),
        order_by: [desc: s.priority, asc: s.created_at],
        select: {e, s}
      )

    Repo.all(query, prefix: project_id)
  end

  def list_running_executions(project_id) do
    query =
      from(e in Models.Execution,
        join: a in Models.Assignment,
        on: a.run_id == e.run_id and a.step_id == e.step_id and a.attempt == e.attempt,
        left_join: r in Models.Result,
        on: r.run_id == e.run_id and r.step_id == e.step_id and r.attempt == e.attempt,
        left_join: h in Models.Heartbeat,
        on: h.run_id == e.run_id and h.step_id == e.step_id and h.attempt == e.attempt,
        where: is_nil(r.attempt),
        distinct: [e.run_id, e.step_id, e.attempt],
        order_by: [e.run_id, e.step_id, e.attempt, desc: h.created_at],
        select: {e, a, h}
      )

    Repo.all(query, prefix: project_id)
  end

  def abandon_execution(project_id, execution) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Repo.insert!(
        %Models.Result{
          run_id: execution.run_id,
          step_id: execution.step_id,
          attempt: execution.attempt,
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
             run_id: execution.run_id,
             step_id: execution.step_id,
             attempt: execution.attempt,
             created_at: DateTime.utc_now()
           },
           prefix: project_id
         ) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  def put_result(project_id, execution_id, result) do
    {run_id, step_id, attempt} = decode_execution_id(execution_id)
    {type, value, extra} = parse_result(result)

    Repo.insert!(
      %Models.Result{
        run_id: run_id,
        step_id: step_id,
        attempt: attempt,
        type: type,
        value: value,
        extra: extra,
        created_at: DateTime.utc_now()
      },
      prefix: project_id
    )
  end

  def get_result(project_id, execution_id) do
    {run_id, step_id, attempt} = decode_execution_id(execution_id)
    clauses = [run_id: run_id, step_id: step_id, attempt: attempt]

    case Repo.get_by(Models.Result, clauses, prefix: project_id) do
      nil -> nil
      result -> compose_result(result)
    end
  end

  def record_dependency(project_id, from, to) do
    {run_id, step_id, attempt} = decode_execution_id(from)
    {dependency_run_id, dependency_step_id, dependency_attempt} = decode_execution_id(to)

    Repo.insert!(
      %Models.Dependency{
        run_id: run_id,
        step_id: step_id,
        attempt: attempt,
        dependency_run_id: dependency_run_id,
        dependency_step_id: dependency_step_id,
        dependency_attempt: dependency_attempt,
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

    execution =
      if cached_step do
        # TODO: check result and handle failed execution? (create new step? and/or reschedule?)
        query =
          from(
            e in Models.Execution,
            where: e.run_id == ^cached_step.run_id and e.step_id == ^cached_step.id,
            order_by: [desc: e.created_at],
            limit: 1
          )

        Repo.one(query, prefix: project_id)
      else
        Repo.insert!(
          %Models.Execution{
            run_id: step.run_id,
            step_id: step.id,
            attempt: 1,
            version: version,
            created_at: now
          },
          prefix: project_id
        )
      end

    {execution.run_id,
     encode_execution_id(execution.run_id, execution.step_id, execution.attempt)}
  end
end

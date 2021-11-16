defmodule Coflux.Project.Store do
  alias Coflux.Project.Models
  alias Coflux.Repo.Projects, as: Repo

  import Ecto.Query, only: [from: 2]

  def list_tasks(project_id) do
    Repo.all(Models.Task, prefix: project_id)
  end

  def list_task_runs(project_id, task_id) do
    query =
      from(
        r in Models.Run,
        where: r.task_id == ^task_id,
        preload: [:initial_step]
      )

    Repo.all(query, prefix: project_id)
  end

  def get_task(project_id, task_id) do
    Repo.get!(Models.Task, task_id, prefix: project_id)
  end

  def get_run(project_id, run_id) do
    Models.Run
    |> Repo.get!(run_id, prefix: project_id)
    |> Repo.preload([
      :task,
      steps: [:cached_step, executions: [:dependencies, :assignment, :result]]
    ])
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
      run = Repo.insert!(%Models.Run{task_id: task_id, tags: run_tags}, prefix: project_id)

      execution_id =
        schedule_step(project_id, run, task.repository, task.target, arguments,
          tags: task_tags,
          priority: priority,
          version: version
        )

      {run.id, execution_id}
    end)
    |> case do
      {:ok, {run_id, execution_id}} ->
        {:ok, run_id, execution_id}
    end
  end

  def schedule_child(project_id, parent_execution_id, repository, target, arguments, opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :keyword)
    cache_key = Keyword.get(opts, :cache_key)

    Repo.transaction(fn ->
      parent_execution = Repo.get!(Models.Execution, parent_execution_id, prefix: project_id)
      parent_step = Repo.get!(Models.Step, parent_execution.step_id, prefix: project_id)
      run = Repo.get!(Models.Run, parent_step.run_id, prefix: project_id)

      schedule_step(project_id, run, repository, target, arguments,
        tags: tags,
        priority: priority,
        version: version,
        parent_id: parent_execution_id,
        cache_key: cache_key
      )
    end)
  end

  def acknowledge_executions(project_id, execution_ids) do
    now = DateTime.utc_now()

    Repo.insert_all(
      Models.Acknowledgment,
      Enum.map(execution_ids, &%{execution_id: &1, created_at: now}),
      prefix: project_id
    )
  end

  def list_pending_executions(project_id) do
    now = DateTime.utc_now()

    query =
      from(e in Models.Execution,
        join: s in assoc(e, :step),
        left_join: a in assoc(e, :assignment),
        where: e.execute_after <= ^now or is_nil(e.execute_after),
        where: is_nil(a.execution_id),
        order_by: [desc: s.priority, asc: s.created_at],
        preload: [:step]
      )

    Repo.all(query, prefix: project_id)
  end

  def list_running_executions(project_id) do
    # TODO: just get latest acknowledgment (if any; use inner_lateral_join?)
    query =
      from(e in Models.Execution,
        join: a in assoc(e, :assignment),
        left_join: r in assoc(e, :result),
        where: is_nil(r.execution_id),
        preload: [:acknowledgments, assignment: a]
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

      execution =
        Repo.insert!(
          %Models.Execution{
            step_id: execution.step_id,
            version: execution.version,
            created_at: now
          },
          prefix: project_id
        )

      execution.id
    end)
  end

  def assign_execution(project_id, execution_id) do
    case Repo.insert(
           %Models.Assignment{
             execution_id: execution_id,
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
    case Repo.get(Models.Result, execution_id, prefix: project_id) do
      nil -> nil
      result -> compose_result(result)
    end
  end

  def record_dependency(project_id, execution_id, dependency_id) do
    Repo.insert!(
      %Models.Dependency{
        execution_id: execution_id,
        dependency_id: dependency_id,
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
    tags = Keyword.fetch!(opts, :tags)
    priority = Keyword.fetch!(opts, :priority)
    version = Keyword.fetch!(opts, :version)
    parent_id = Keyword.get(opts, :parent_id)
    cache_key = Keyword.get(opts, :cache_key)
    now = DateTime.utc_now()

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
          parent_id: parent_id,
          repository: repository,
          target: target,
          arguments: Enum.map(arguments, &parse_argument/1),
          tags: run.tags ++ tags,
          priority: priority,
          cache_key: unless(cached_step, do: cache_key),
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
            where: e.step_id == ^cached_step.id,
            order_by: [desc: e.created_at],
            limit: 1
          )

        Repo.one(query, prefix: project_id)
      else
        Repo.insert!(
          %Models.Execution{
            step_id: step.id,
            version: version,
            created_at: now
          },
          prefix: project_id
        )
      end

    execution.id
  end
end

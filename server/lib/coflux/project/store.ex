defmodule Coflux.Project.Store do
  alias Coflux.Project.Models
  alias Coflux.Repo.Projects, as: Repo

  import Ecto.Query, only: [from: 2]

  def list_tasks(project_id) do
    Repo.all(Models.Task, prefix: project_id)
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
          created_at: DateTime.truncate(DateTime.utc_now(), :second)
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

      schedule_step(project_id, run, task.repository, task.target, arguments,
        tags: task_tags,
        priority: priority,
        version: version
      )
    end)
  end

  def schedule_child(project_id, parent_execution_id, repository, target, arguments, opts \\ []) do
    tags = Keyword.get(opts, :tags, [])
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :keyword)

    Repo.transaction(fn ->
      parent_execution = Repo.get!(Models.Execution, parent_execution_id, prefix: project_id)
      parent_step = Repo.get!(Models.Step, parent_execution.step_id, prefix: project_id)
      run = Repo.get!(Models.Run, parent_step.run_id, prefix: project_id)

      schedule_step(project_id, run, repository, target, arguments,
        tags: tags,
        priority: priority,
        version: version,
        parent_id: parent_execution_id
      )
    end)
  end

  def list_pending_executions(project_id) do
    query =
      from(e in Models.Execution,
        join: s in assoc(e, :step),
        left_join: a in assoc(e, :assignment),
        where: e.execute_after <= ^utc_now() or is_nil(e.execute_after),
        where: is_nil(a.execution_id),
        order_by: [desc: s.priority, asc: s.created_at],
        preload: [step: {s, [:arguments]}]
      )

    Repo.all(query, prefix: project_id)
  end

  def assign_execution(project_id, execution_id) do
    case Repo.insert(
           %Models.Assignment{
             execution_id: execution_id,
             created_at: utc_now()
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
        created_at: utc_now()
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

  defp parse_result(result) do
    case result do
      {:raw, value} -> {0, Jason.encode!(value), nil}
      {:blob, hash} when is_binary(hash) -> {1, hash, nil}
      {:result, execution_id} when is_binary(execution_id) -> {2, execution_id, nil}
      {:failed, error, stacktrace} -> {3, error, stacktrace}
    end
  end

  defp compose_result(result) do
    case result.type do
      0 -> {:raw, Jason.decode!(result.value)}
      1 -> {:blob, result.value}
      2 -> {:result, result.value}
      3 -> {:failed, result.value, result.extra}
    end
  end

  defp parse_argument({type, value}) do
    case type do
      :raw -> {0, Jason.encode!(value)}
      :blob when is_binary(value) -> {1, value}
      :result when is_binary(value) -> {2, value}
    end
  end

  defp schedule_step(project_id, run, repository, target, arguments, opts) do
    tags = Keyword.fetch!(opts, :tags)
    priority = Keyword.fetch!(opts, :priority)
    version = Keyword.fetch!(opts, :version)
    parent_id = Keyword.get(opts, :parent_id)
    now = utc_now()

    step =
      Repo.insert!(
        %Models.Step{
          run_id: run.id,
          parent_id: parent_id,
          repository: repository,
          target: target,
          tags: run.tags ++ tags,
          priority: priority,
          created_at: now
        },
        prefix: project_id
      )

    step_arguments =
      arguments
      |> Enum.map(&parse_argument/1)
      |> Enum.with_index()
      |> Enum.map(fn {{type, value}, index} ->
        %{step_id: step.id, index: index, type: type, value: value}
      end)

    Repo.insert_all(Models.StepArgument, step_arguments, prefix: project_id)

    execution =
      Repo.insert!(
        %Models.Execution{
          step_id: step.id,
          version: version,
          created_at: now
        },
        prefix: project_id
      )

    execution.id
  end

  defp utc_now() do
    DateTime.truncate(DateTime.utc_now(), :second)
  end
end

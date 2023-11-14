defmodule Coflux.Topics.Task do
  use Topical.Topic,
    route: [
      "projects",
      :project_id,
      "environments",
      :environment_name,
      "tasks",
      :repository,
      :target
    ]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    repository = Keyword.fetch!(params, :repository)
    target_name = Keyword.fetch!(params, :target)

    case Orchestration.subscribe_task(
           project_id,
           environment_name,
           repository,
           target_name,
           self()
         ) do
      {:ok, target, runs, _ref} ->
        runs =
          Map.new(runs, fn {run_id, created_at} ->
            {run_id, %{id: run_id, createdAt: created_at}}
          end)

        task = %{
          repository: repository,
          target: target_name,
          parameters:
            Enum.map(target.parameters, fn {name, default, annotation} ->
              %{name: name, default: default, annotation: annotation}
            end),
          runs: runs
        }

        {:ok,
         Topic.new(task, %{
           project_id: project_id,
           environment_name: environment_name,
           repository: repository,
           target: target_name
         })}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def handle_info({:topic, _ref, {:run, run_id, created_at}}, topic) do
    topic =
      Topic.set(
        topic,
        [:runs, run_id],
        %{id: run_id, createdAt: created_at}
      )

    {:ok, topic}
  end

  def handle_execute("start_run", {arguments}, topic, _context) do
    %{
      project_id: project_id,
      environment_name: environment_name,
      repository: repository,
      target: target
    } = topic.state

    arguments = Enum.map(arguments, &parse_argument/1)

    case Orchestration.schedule(project_id, environment_name, repository, target, arguments) do
      {:ok, run_id, _step_id, _execution_id} ->
        {:ok, run_id, topic}
    end
  end

  defp parse_argument(argument) do
    case argument do
      ["json", value] -> {:raw, "json", value}
    end
  end
end

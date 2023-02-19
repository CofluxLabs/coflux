defmodule Coflux.Project.Topics.Task do
  use Topical.Topic,
    route: "projects/:project_id/environments/:environment_name/tasks/:repository/:target"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener
  alias Coflux.Project

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    repository = Keyword.fetch!(params, :repository)
    target = Keyword.fetch!(params, :target)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.Manifest, Models.Step]
      )

    # TODO: find latest manifest with target
    with {:ok, environment} <- Store.get_environment_by_name(project_id, environment_name),
         {:ok, manifest} <- Store.find_manifest(project_id, repository, environment.id),
         {:ok, runs} <- Store.list_task_runs(project_id, repository, target, environment.id) do
      case Map.fetch(manifest.tasks, target) do
        {:ok, parameters} ->
          runs =
            Map.new(runs, fn run ->
              {run.id, %{id: run.id, createdAt: run.created_at}}
            end)

          task = %{
            repository: repository,
            version: manifest.version,
            target: target,
            parameters: parameters,
            runs: runs
          }

          topic =
            Topic.new(task, %{
              project_id: project_id,
              repository: repository,
              target: target,
              environment_name: environment_name
            })

          {:ok, topic}

        :error ->
          {:error, :not_found}
      end
    end
  end

  def handle_info({:insert, _ref, %Models.Manifest{} = manifest}, topic) do
    if manifest.repository == topic.state.repository &&
         Map.has_key?(manifest.tasks, topic.state.target) do
      case Map.fetch(manifest.tasks, topic.state.target) do
        {:ok, parameters} ->
          topic =
            topic
            |> Topic.set([:parameters], parameters)
            |> Topic.set([:version], manifest.version)

          {:ok, topic}

        :error ->
          # TODO: remove task?
          {:ok, topic}
      end
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Step{} = step}, topic) do
    if step.repository == topic.state.repository && step.target == topic.state.target &&
         is_nil(step.parent_attempt) do
      topic =
        Topic.set(topic, [:runs, step.run_id], %{id: step.run_id, createdAt: step.created_at})

      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_execute("start_run", {arguments}, topic, _context) do
    arguments = Enum.map(arguments, &parse_argument/1)

    # TODO: prevent scheduling unrecognised tasks?
    with {:ok, environment} <-
           Project.get_environment_by_name(topic.state.project_id, topic.state.environment_name) do
      case Project.schedule_task(
             topic.state.project_id,
             environment.id,
             topic.state.repository,
             topic.state.target,
             arguments
           ) do
        {:ok, run_id} ->
          {:ok, run_id, topic}
      end
    end
  end

  defp parse_argument(argument) do
    case argument do
      ["json", value] -> {:json, value}
      ["blob", key] -> {:blob, key}
      ["result", execution_id] -> {:result, execution_id}
    end
  end
end

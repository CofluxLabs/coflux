defmodule Coflux.Topics.Sensor do
  use Topical.Topic,
    route: [
      "projects",
      :project_id,
      "environments",
      :environment_name,
      "sensors",
      :repository,
      :target
    ]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    repository = Keyword.fetch!(params, :repository)
    target_name = Keyword.fetch!(params, :target)

    case Orchestration.subscribe_sensor(
           project_id,
           environment_name,
           repository,
           target_name,
           self()
         ) do
      {:ok, activated, executions, runs, _ref} ->
        executions =
          Map.new(executions, fn {execution_id, created_at} ->
            {execution_id, %{createdAt: created_at}}
          end)

        runs =
          Map.new(runs, fn {run_id, created_at, repository, target} ->
            {run_id,
             %{
               createdAt: created_at,
               repository: repository,
               target: target
             }}
          end)

        sensor = %{
          repository: repository,
          target: target_name,
          activated: activated,
          executions: executions,
          runs: runs
        }

        {:ok,
         Topic.new(sensor, %{
           project_id: project_id,
           environment_name: environment_name,
           repository: repository,
           target: target_name
         })}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def handle_info({:topic, _ref, {:execution, execution_id, created_at}}, topic) do
    topic =
      Topic.set(
        topic,
        [:executions, Integer.to_string(execution_id)],
        %{createdAt: created_at}
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:run, run_id, created_at, repository, target}}, topic) do
    # TODO: limit number of runs
    topic =
      Topic.set(
        topic,
        [:runs, run_id],
        %{createdAt: created_at, repository: repository, target: target}
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:activated, activated}}, topic) do
    topic = Topic.set(topic, [:activated], activated)
    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:assignment, _execution_id, _assigned_at}}, topic) do
    # TODO: update execution?
    {:ok, topic}
  end

  def handle_execute("activate", {}, topic, _context) do
    %{
      project_id: project_id,
      environment_name: environment_name,
      repository: repository,
      target: target
    } = topic.state

    case Orchestration.activate_sensor(project_id, environment_name, repository, target) do
      :ok ->
        {:ok, nil, topic}
    end
  end

  def handle_execute("deactivate", {}, topic, _context) do
    %{
      project_id: project_id,
      environment_name: environment_name,
      repository: repository,
      target: target
    } = topic.state

    case Orchestration.deactivate_sensor(project_id, environment_name, repository, target) do
      :ok ->
        {:ok, nil, topic}
    end
  end
end

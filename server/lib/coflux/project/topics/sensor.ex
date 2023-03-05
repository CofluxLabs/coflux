defmodule Coflux.Project.Topics.Sensor do
  use Topical.Topic,
    route: "projects/:project_id/environments/:environment_name/sensors/:repository/:target"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

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
        [
          Models.SensorActivation,
          Models.SensorDeactivation,
          Models.SensorIteration,
          Models.Run
        ]
      )

    # TODO: handle no environment
    with {:ok, environment} <- Store.get_environment_by_name(project_id, environment_name),
         {:ok, activation_iteration} <-
           Store.get_sensor_activation(project_id, repository, target, environment.id),
         {:ok, sensor_runs} <-
           Store.list_sensor_runs(project_id, repository, target, environment.id) do
      {activation, execution_id} =
        case activation_iteration do
          {sensor_activation, iteration} ->
            {%{
               id: sensor_activation.id,
               createdAt: sensor_activation.created_at
             }, iteration.execution_id}

          nil ->
            {nil, nil}
        end

      runs =
        Enum.map(sensor_runs, fn {run, step} ->
          %{
            id: run.id,
            createdAt: run.created_at,
            repository: step.repository,
            target: step.target,
            executionId: run.execution_id
          }
        end)

      sensor = %{
        repository: repository,
        target: target,
        activation: activation,
        runs: runs
      }

      topic =
        Topic.new(sensor, %{
          project_id: project_id,
          repository: repository,
          target: target,
          environment_id: environment.id,
          execution_id: execution_id
        })

      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorActivation{} = activation}, topic) do
    if activation.repository == topic.state.repository && activation.target == topic.state.target &&
         activation.environment_id == topic.state.environment_id do
      topic =
        Topic.set(topic, [:activation], %{id: activation.id, createdAt: activation.created_at})

      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorDeactivation{} = deactivation}, topic) do
    if topic.value.activation && deactivation.activation_id == topic.value.activation.id do
      topic = Topic.set(topic, [:activation], nil)
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorIteration{} = iteration}, topic) do
    if topic.value.activation && iteration.activation_id == topic.value.activation.id do
      topic = put_in(topic.state.execution_id, iteration.execution_id)
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Run{} = run}, topic) do
    if run.execution_id == topic.state.execution_id do
      case Store.get_run_initial_step(topic.state.project_id, run.id) do
        {:ok, step} ->
          topic = Topic.insert(topic, [:runs], 0, %{
            id: run.id,
            createdAt: run.created_at,
            repository: step.repository,
            target: step.target,
            executionId: run.execution_id
          })
          {:ok, topic}
      end
    else
      {:ok, topic}
    end
  end

  def handle_execute("activate", {}, topic, _context) do
    %{
      project_id: project_id,
      environment_id: environment_id,
      repository: repository,
      target: target
    } = topic.state

    case Store.activate_sensor(project_id, environment_id, repository, target) do
      {:ok, activation_id} ->
        {:ok, activation_id, topic}
    end
  end

  def handle_execute("deactivate", {activation_id}, topic, _context) do
    case Store.deactivate_sensor(topic.state.project_id, activation_id) do
      :ok ->
        {:ok, nil, topic}
    end
  end
end

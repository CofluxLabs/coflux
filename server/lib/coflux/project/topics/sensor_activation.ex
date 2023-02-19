defmodule Coflux.Project.Topics.SensorActivation do
  use Topical.Topic, route: "projects/:project_id/sensor_activations/:activation_id"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    activation_id = Keyword.fetch!(params, :activation_id)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.Run, Models.SensorIteration, Models.SensorDeactivation]
      )

    with {:ok, activation} <- Store.get_sensor_activation(project_id, activation_id),
         {:ok, deactivation} <- Store.get_sensor_deactivation(project_id, activation_id),
         {:ok, runs} <- Store.list_sensor_runs(project_id, activation_id) do
      runs =
        Map.new(runs, fn run ->
          {run.id, %{id: run.id, createdAt: run.created_at}}
        end)

      sensor =
        activation
        |> Map.take([:repository, :target])
        |> Map.put(:createdAt, activation.created_at)
        |> Map.put(:deactivatedAt, if(deactivation, do: deactivation.created_at))
        |> Map.put(:runs, runs)

      execution_id =
        case Store.latest_sensor_execution(project_id, activation_id) do
          {:ok, %{id: execution_id}} -> execution_id
          {:error, :not_found} -> nil
        end

      topic = Topic.new(sensor, %{activation_id: activation_id, execution_id: execution_id})
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Run{} = run}, topic) do
    if run.execution_id && run.execution_id == topic.state.execution_id do
      topic = Topic.set(topic, [:runs, run.id], %{id: run.id, createdAt: run.created_at})
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorIteration{} = iteration}, topic) do
    if iteration.activation_id == topic.state.activation_id do
      topic = put_in(topic.state.execution_id, iteration.execution_id)
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorDeactivation{} = deactivation}, topic) do
    topic = Topic.set(topic, [:deactivatedAt], deactivation.created_at)
    {:ok, topic}
  end
end

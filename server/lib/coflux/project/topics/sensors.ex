defmodule Coflux.Project.Topics.Sensors do
  use Topical.Topic, route: "projects/:project_id/sensors"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.SensorActivation, Models.SensorDeactivation]
      )

    case Store.list_sensor_activations(project_id) do
      {:ok, activations} ->
        value =
          Map.new(activations, fn activation ->
            {activation.id, Map.take(activation, [:repository, :target])}
          end)

        topic = Topic.new(value)

        {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SensorActivation{} = activation}, topic) do
    topic = Topic.set(topic, [activation.id], Map.take(activation, [:repository, :target]))
    {:ok, topic}
  end

  def handle_info({:insert, _ref, %Models.SensorDeactivation{} = deactivation}, topic) do
    topic = Topic.unset(topic, [], deactivation.activation_id)
    {:ok, topic}
  end
end

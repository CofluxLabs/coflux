defmodule Coflux.Project.Observer.Topics.Sensors do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.SensorActivation, Models.SensorDeactivation]

  def load(project_id, []) do
    case Store.list_sensor_activations(project_id) do
      {:ok, activations} ->
        value =
          Map.new(activations, fn activation ->
            {activation.id, Map.take(activation, [:repository, :target, :tags])}
          end)

        {:ok, value, nil}
    end
  end

  def handle_insert(%Models.SensorActivation{} = activation, _value, state) do
    {:ok, [{[activation.id], Map.take(activation, [:repository, :target, :tags])}], state}
  end

  def handle_insert(%Models.SensorDeactivation{} = deactivation, _value, state) do
    {:ok, [{[deactivation.activation_id], nil}], state}
  end
end

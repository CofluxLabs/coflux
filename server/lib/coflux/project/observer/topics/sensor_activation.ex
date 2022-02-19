defmodule Coflux.Project.Observer.Topics.SensorActivation do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Run, Models.SensorIteration, Models.SensorDeactivation]

  def load(project_id, [activation_id]) do
    with {:ok, activation} <- Store.get_sensor_activation(project_id, activation_id),
         {:ok, deactivation} <- Store.get_sensor_deactivation(project_id, activation_id),
         {:ok, runs} <- Store.list_sensor_runs(project_id, activation_id) do
      runs =
        Map.new(runs, fn run ->
          {run.id, Map.take(run, [:id, :created_at])}
        end)

      sensor =
        activation
        |> Map.take([:repository, :target, :tags, :created_at])
        |> Map.put(:deactivated_at, if(deactivation, do: deactivation.created_at))
        |> Map.put(:runs, runs)

      execution_id =
        case Store.latest_sensor_execution(project_id, activation_id) do
          {:ok, %{id: execution_id}} -> execution_id
          {:error, :not_found} -> nil
        end

      {:ok, sensor, %{activation_id: activation_id, execution_id: execution_id}}
    end
  end

  def handle_insert(%Models.Run{} = run, _value, state) do
    if run.execution_id && run.execution_id == state.execution_id do
      {:ok, [{[:runs, run.id], Map.take(run, [:id, :created_at])}], state}
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.SensorIteration{} = iteration, _value, state) do
    if iteration.activation_id == state.activation_id do
      {:ok, [], Map.put(state, :execution_id, iteration.execution_id)}
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.SensorDeactivation{} = deactivation, _value, state) do
    {:ok, [{[:deactivated_at], deactivation.created_at}], state}
  end
end

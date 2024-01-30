defmodule Coflux.Observation do
  alias Coflux.Observation

  def subscribe(project_id, environment_name, run_id, pid) do
    call_server(project_id, environment_name, {:subscribe, run_id, pid})
  end

  def unsubscribe(project_id, environment_name, ref) do
    cast_server(project_id, environment_name, {:unsubscribe, ref})
  end

  def write(project_id, environment_name, run_id, messages) do
    cast_server(project_id, environment_name, {:write, run_id, messages})
  end

  defp call_server(project_id, environment, request) do
    case Observation.Supervisor.get_server(project_id, environment) do
      {:ok, server} ->
        GenServer.call(server, request)
    end
  end

  defp cast_server(project_id, environment, request) do
    case Observation.Supervisor.get_server(project_id, environment) do
      {:ok, server} ->
        GenServer.cast(server, request)
    end
  end
end

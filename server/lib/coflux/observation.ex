defmodule Coflux.Observation do
  alias Coflux.Observation

  def subscribe(project_id, run_id, pid) do
    call_server(project_id, {:subscribe, run_id, pid})
  end

  def unsubscribe(project_id, ref) do
    cast_server(project_id, {:unsubscribe, ref})
  end

  def write(project_id, run_id, messages) do
    cast_server(project_id, {:write, run_id, messages})
  end

  defp call_server(project_id, request) do
    case Observation.Supervisor.get_server(project_id) do
      {:ok, server} ->
        GenServer.call(server, request)
    end
  end

  defp cast_server(project_id, request) do
    case Observation.Supervisor.get_server(project_id) do
      {:ok, server} ->
        GenServer.cast(server, request)
    end
  end
end

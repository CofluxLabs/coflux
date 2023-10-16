defmodule Coflux.Logging do
  alias Coflux.Logging

  def subscribe(project_id, environment_name, run_id, pid) do
    call_server(project_id, environment_name, run_id, {:subscribe, pid, nil})
  end

  def unsubscribe(project_id, environment_name, run_id, ref) do
    cast_server(project_id, environment_name, run_id, {:unsubscribe, ref})
  end

  def write(project_id, environment_name, run_id, messages) do
    cast_server(project_id, environment_name, run_id, {:write, messages})
  end

  defp call_server(project_id, environment, run_id, request) do
    case Logging.Supervisor.get_server(project_id, environment, run_id) do
      {:ok, server} ->
        GenServer.call(server, request)
    end
  end

  defp cast_server(project_id, environment, run_id, request) do
    case Logging.Supervisor.get_server(project_id, environment, run_id) do
      {:ok, server} ->
        GenServer.cast(server, request)
    end
  end
end

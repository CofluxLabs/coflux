defmodule Coflux do
  alias Coflux.Orchestration

  def inspect(project_id) do
    {:ok, pid} = Orchestration.Supervisor.get_server(project_id)
    :sys.get_state(pid)
  end
end

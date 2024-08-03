defmodule Coflux do
  alias Coflux.Orchestration

  def inspect(project_id, environment \\ "development") do
    {:ok, pid} = Orchestration.Supervisor.get_server(project_id, environment)
    :sys.get_state(pid)
  end
end

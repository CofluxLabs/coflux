defmodule Coflux.Listener do
  use GenServer

  alias Postgrex.Notifications
  alias Coflux.Repo.Projects, as: Repo
  alias Coflux.Project.Supervisor, as: ProjectSupervisor

  @event_name "insert"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, {}, opts)
  end

  def init({}) do
    config = Keyword.put(Repo.config(), :auto_reconnect, true)

    with {:ok, pid} <- Notifications.start_link(config),
         {:ok, ref} <- Notifications.listen(pid, @event_name) do
      {:ok, {pid, ref}}
    end
  end

  def handle_info({:notification, _pid, _ref, _channel, payload}, state) do
    [identifier, argument] = String.split(payload, ":", parts: 2)
    [project_id, table] = String.split(identifier, ".", parts: 2)

    with {:ok, pid} <- ProjectSupervisor.get_server(project_id) do
      GenServer.cast(pid, {:insert, table, argument})
    end

    {:noreply, state}
  end
end

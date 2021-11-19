defmodule Coflux.Listener do
  use GenServer

  alias Postgrex.Notifications

  def start_link(opts) do
    {repo, opts} = Keyword.pop!(opts, :repo)
    GenServer.start_link(__MODULE__, repo, opts)
  end

  def subscribe(server, project_id, pid) do
    GenServer.call(server, {:subscribe, project_id, pid})
  end

  def init(repo) do
    config = Keyword.put(repo.config(), :auto_reconnect, true)

    with {:ok, pid} <- Notifications.start_link(config),
         {:ok, _ref} <- Notifications.listen(pid, "insert") do
      {:ok, %{project_pids: %{}, ref_project: %{}}}
    end
  end

  def handle_call({:subscribe, project_id, pid}, _from, state) do
    ref = Process.monitor(pid)

    state =
      state
      |> update_in([:project_pids, Access.key(project_id, %{})], &Map.put(&1, pid, ref))
      |> put_in([:ref_project, ref], project_id)

    {:reply, :ok, state}
  end

  def handle_info({:notification, _pid, _ref, _channel, payload}, state) do
    [identifier, json] = String.split(payload, ":", parts: 2)
    [project_id, table] = String.split(identifier, ".", parts: 2)
    table_atom = String.to_atom(table)
    data = Jason.decode!(json, keys: :atoms!)

    state.project_pids
    |> Map.get(project_id, %{})
    |> Enum.each(fn {pid, ref} ->
      send(pid, {:insert, ref, table_atom, data})
    end)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    project_id = Map.fetch!(state.ref_project, ref)
    {pids, state} = pop_in(state.project_pids[project_id])
    pids = Map.delete(pids, pid)

    state =
      if Enum.empty?(pids) do
        state
      else
        put_in(state.project_pids[project_id], pids)
      end

    {:noreply, state}
  end
end

defmodule Coflux.Observation.Server do
  use GenServer, restart: :transient

  alias Coflux.Store
  alias Coflux.Observation.Messages

  def start_link(opts) do
    {project_id, opts} = Keyword.pop!(opts, :project_id)
    GenServer.start_link(__MODULE__, project_id, opts)
  end

  def init(project_id) do
    case Store.open(project_id, "observation") do
      {:ok, db} ->
        {:ok, %{db: db, subscribers: %{}}}
    end
  end

  def terminate(_reason, state) do
    Store.close(state.db)
  end

  def handle_cast({:write, run_id, messages}, state) do
    :ok = Messages.put_messages(state.db, run_id, messages)

    state.subscribers
    |> Map.get(run_id, %{})
    |> Enum.each(fn {ref, pid} ->
      send(pid, {:messages, ref, messages})
    end)

    {:noreply, state}
  end

  def handle_cast({:unsubscribe, ref}, state) do
    state = remove_subscriber(state, ref)
    Process.demonitor(ref)
    {:noreply, state}
  end

  defp remove_subscriber(state, ref) do
    Map.update!(state, :subscribers, fn subscribers ->
      Enum.reduce(subscribers, subscribers, fn {run_id, run_subscribers}, subscribers ->
        run_subscribers = Map.delete(run_subscribers, ref)

        if Enum.empty?(run_subscribers) do
          subscribers
        else
          Map.put(subscribers, run_id, run_subscribers)
        end
      end)
    end)
  end

  # TODO: support pagination? filtering by execution?
  def handle_call({:subscribe, run_id, pid}, _from, state) do
    {:ok, messages} = Messages.get_messages(state.db, run_id)

    ref = Process.monitor(pid)
    state = put_in(state, [:subscribers, Access.key(run_id, %{}), ref], pid)

    {:reply, {:ok, ref, messages}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state = remove_subscriber(state, ref)
    {:noreply, state}
  end
end

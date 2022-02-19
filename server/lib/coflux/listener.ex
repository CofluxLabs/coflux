defmodule Coflux.Listener do
  use GenServer

  alias Postgrex.Notifications
  alias Ecto.Changeset

  def start_link(opts) do
    {repo, opts} = Keyword.pop!(opts, :repo)
    GenServer.start_link(__MODULE__, repo, opts)
  end

  def subscribe(server, project_id, pid, models) do
    GenServer.call(server, {:subscribe, project_id, pid, models})
  end

  def init(repo) do
    config = Keyword.put(repo.config(), :auto_reconnect, true)

    with {:ok, pid} <- Notifications.start_link(config),
         {:ok, _ref} <- Notifications.listen(pid, "insert") do
      {:ok, %{project_pids: %{}, ref_project: %{}, models: %{}}}
    end
  end

  def handle_call({:subscribe, project_id, pid, models}, _from, state) do
    ref = Process.monitor(pid)

    state =
      models
      |> Enum.reduce(state, fn model, state ->
        table = model.__schema__(:source)

        state
        |> put_in([:project_pids, Access.key(project_id, %{}), Access.key(table, %{}), pid], ref)
        |> put_in([:models, table], model)
      end)
      |> put_in([:ref_project, ref], project_id)

    {:reply, :ok, state}
  end

  def handle_info({:notification, _pid, _ref, _channel, payload}, state) do
    [identifier, json] = String.split(payload, ":", parts: 2)
    [project_id, table] = String.split(identifier, ".", parts: 2)

    subscriptions =
      state.project_pids
      |> Map.get(project_id, %{})
      |> Map.get(table, %{})

    if Enum.any?(subscriptions) do
      data =
        json
        |> Jason.decode!()
        |> Map.new(fn {key, value} ->
          {String.to_existing_atom(key), value}
        end)

      model = load_model(state.models[table], data)

      Enum.each(subscriptions, fn {pid, ref} ->
        send(pid, {:insert, ref, model})
      end)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {project_id, state} = pop_in(state.ref_project[ref])
    {table_pids, state} = pop_in(state.project_pids[project_id])

    table_pids =
      Enum.reduce(table_pids, %{}, fn {table, pids}, table_pids ->
        pids = Map.delete(pids, pid)

        if Enum.empty?(pids) do
          table_pids
        else
          Map.put(table_pids, table, pids)
        end
      end)

    state =
      if Enum.empty?(table_pids) do
        state
      else
        put_in(state.project_pids[project_id], table_pids)
      end

    {:noreply, state}
  end

  defp load_model(type, data) do
    type
    |> struct()
    |> Changeset.cast(data, type.__schema__(:fields))
    |> Changeset.apply_changes()
  end
end

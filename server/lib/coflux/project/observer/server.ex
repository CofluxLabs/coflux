defmodule Coflux.Project.Observer.Server do
  use GenServer, restart: :transient

  alias Coflux.Listener
  alias Coflux.Project.Observer.Topics

  @topics %{
    "environments" => Topics.Environments,
    "repositories" => Topics.Repositories,
    "run_logs" => Topics.RunLogs,
    "run" => Topics.Run,
    "sensor_activation" => Topics.SensorActivation,
    "sensors" => Topics.Sensors,
    "task" => Topics.Task
  }

  def start_link(opts) do
    {project_id, topic, arguments} = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, {project_id, topic, arguments}, opts)
  end

  def init({project_id, topic, arguments}) do
    IO.puts("Starting observer (#{project_id}, #{topic}; #{inspect(arguments)})...")

    case Map.fetch(@topics, topic) do
      {:ok, module} ->
        :ok = Listener.subscribe(Coflux.ProjectsListener, project_id, self(), module.models())

        case module.load(project_id, arguments) do
          {:ok, value, module_state} ->
            # TODO: timeout
            {:ok,
             %{
               project_id: project_id,
               module: module,
               subscribers: %{},
               value: value,
               module_state: module_state
             }}

          {:error, error} ->
            {:stop, error}
        end

      :error ->
        {:stop, :not_found}
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    ref = Process.monitor(pid)
    state = put_in(state, [:subscribers, ref], pid)
    {:reply, {:ok, ref, state.value}, state}
  end

  def handle_call({:unsubscribe, ref}, _from, state) do
    state = unsubscribe(state, ref)
    Process.demonitor(ref)
    {:reply, :ok, state}
  end

  def handle_info({:insert, _ref, model}, state) do
    {:ok, updates, module_state} =
      state.module.handle_insert(model, state.value, state.module_state)

    value =
      Enum.reduce(updates, state.value, fn {path, path_value}, value ->
        if is_nil(path_value) do
          {_, state} = pop_in(value, path)
          state
        else
          put_in(value, path, path_value)
        end
      end)

    state =
      state
      |> Map.put(:value, value)
      |> Map.put(:module_state, module_state)

    Enum.each(updates, fn {path, path_value} ->
      notify_subscribers(state.subscribers, path, path_value)
    end)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, unsubscribe(state, ref)}
  end

  defp unsubscribe(state, ref) do
    {_, state} = pop_in(state.subscribers[ref])
    state
  end

  defp notify_subscribers(subscribers, path, new_value) do
    Enum.each(subscribers, fn {ref, pid} ->
      send(pid, {:update, ref, path, new_value})
    end)
  end
end

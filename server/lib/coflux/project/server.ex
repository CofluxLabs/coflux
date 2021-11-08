defmodule Coflux.Project.Server do
  use GenServer, restart: :transient

  defmodule State do
    defstruct targets: %{}, executions: %{}
  end

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, {project_id}, opts)
  end

  def init({project_id}) do
    IO.puts("Project server started (#{project_id}).")
    {:ok, %State{}}
  end

  def handle_call({:schedule, target, arguments, _from_execution_id}, _from, state) do
    # TODO: record execution
    case Map.fetch(state.targets, target) do
      {:ok, pids} ->
        pid = Enum.random(pids)
        execution_id = UUID.uuid4()
        send(pid, {:execute, execution_id, target, arguments})

        state =
          Map.update!(state, :executions, fn executions ->
            Map.put(executions, execution_id, %{result: nil, waiting: []})
          end)

        {:reply, {:ok, execution_id}, state}

      :error ->
        # TODO: queue execution? (and return execution_id)
        {:reply, {:error, :not_registered}, state}
    end
  end

  def handle_call({:put_result, execution_id, result}, _from, state) do
    # TODO: return error if result is already set?
    # TODO: record in database
    waiting = state.executions[execution_id].waiting
    state = put_in(state.executions[execution_id].result, result)
    state = put_in(state.executions[execution_id].waiting, [])

    state =
      if waiting do
        case get_result(state, execution_id) do
          {:ok, result} ->
            Enum.each(waiting, &GenServer.reply(&1, {:ok, result}))
            state

          {:pending, execution_id} ->
            update_in(state.executions[execution_id].waiting, &Enum.concat(waiting, &1))
        end
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call({:get_result, execution_id}, from, state) do
    case get_result(state, execution_id) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:pending, execution_id} ->
        state = update_in(state.executions[execution_id].waiting, &[from | &1])
        {:noreply, state}
    end
  end

  def handle_call({:register, new_targets, pid}, _from, state) do
    _ref = Process.monitor(pid)

    state =
      Map.update!(state, :targets, fn targets ->
        Enum.reduce(new_targets, targets, fn {target, _}, targets ->
          targets
          |> Map.put_new(target, MapSet.new())
          |> Map.update!(target, &MapSet.put(&1, pid))
        end)
      end)

    {:reply, :ok, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      Map.update!(state, :targets, fn targets ->
        Map.new(targets, fn {target, pids} -> {target, MapSet.delete(pids, pid)} end)
      end)

    {:noreply, state}
  end

  defp get_result(state, execution_id) do
    case Map.fetch!(state.executions, execution_id).result do
      nil ->
        {:pending, execution_id}

      {:completed, {:res, execution_id}} ->
        get_result(state, execution_id)

      result ->
        {:ok, result}
    end
  end
end

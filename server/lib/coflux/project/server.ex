defmodule Coflux.Project.Server do
  use GenServer, restart: :transient

  alias Coflux.Project.Store

  defmodule State do
    defstruct project_id: nil, targets: %{}, executions: %{}
  end

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, {project_id}, opts)
  end

  def init({project_id}) do
    IO.puts("Project server started (#{project_id}).")
    {:ok, %State{project_id: project_id}}
  end

  def handle_call({:register_targets, repository, version, new_targets, pid}, _from, state) do
    _ref = Process.monitor(pid)

    state =
      Enum.reduce(new_targets, state, fn {target, _config}, state ->
        put_in(state, [Access.key(:targets), Access.key({repository, target}, %{}), pid], version)
      end)

    state = try_schedule_executions(state)

    {:reply, :ok, state}
  end

  def handle_call({:get_result, execution_id}, from, state) do
    # TODO: do this outside the server?
    case get_result(state.project_id, execution_id) do
      {:pending, execution_id} ->
        state =
          update_in(
            state,
            [Access.key(:executions), Access.key(execution_id, [])],
            &[from | &1]
          )

        {:noreply, state}

      {:resolved, result} ->
        {:reply, result, state}
    end
  end

  def handle_cast({:insert, table, argument}, state) do
    state =
      case table do
        "executions" -> try_schedule_executions(state)
        "results" -> try_notify_results(state, argument)
        _other -> state
      end

    {:noreply, state}
  end

  defp try_schedule_executions(state) do
    state.project_id
    |> Store.list_pending_executions()
    |> Enum.each(fn execution ->
      step = execution.step

      with {:ok, pid_map} <- Map.fetch(state.targets, {step.repository, step.target}),
           {:ok, pid} <- find_agent(pid_map),
           :ok <- Store.assign_execution(state.project_id, execution.id) do
        arguments = prepare_arguments(step.arguments)
        send(pid, {:execute, execution.id, step.target, arguments})
      end
    end)

    state
  end

  defp find_agent(pid_map) do
    # TODO: filter against version (and tags)
    if Enum.empty?(pid_map) do
      :error
    else
      {:ok, Enum.random(Map.keys(pid_map))}
    end
  end

  defp prepare_arguments(arguments) do
    Enum.map(arguments, fn argument ->
      case argument.type do
        0 -> {:raw, Jason.decode!(argument.value)}
        1 -> {:blob, argument.value}
        2 -> {:result, argument.value}
      end
    end)
  end

  defp try_notify_results(state, execution_id) do
    Map.update!(state, :executions, fn executions ->
      case Map.pop(executions, execution_id) do
        {nil, executions} ->
          executions

        {froms, executions} ->
          case get_result(state.project_id, execution_id) do
            {:pending, execution_id} ->
              Map.put(executions, execution_id, froms)

            {:resolved, result} ->
              Enum.each(froms, &GenServer.reply(&1, result))
              executions
          end
      end
    end)
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      Map.update!(state, :targets, fn targets ->
        Map.new(targets, fn {target, pids} -> {target, Map.delete(pids, pid)} end)
      end)

    {:noreply, state}
  end

  defp get_result(project_id, execution_id) do
    case Store.get_result(project_id, execution_id) do
      nil -> {:pending, execution_id}
      {:result, execution_id} -> get_result(project_id, execution_id)
      result -> {:resolved, result}
    end
  end
end

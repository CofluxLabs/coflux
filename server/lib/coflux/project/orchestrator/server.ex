defmodule Coflux.Project.Orchestrator.Server do
  use GenServer, restart: :transient

  alias Coflux.Project.Models
  alias Coflux.Project.Store
  alias Coflux.Listener

  defmodule State do
    defstruct project_id: nil, targets: %{}, waiting: %{}, executions: %{}
  end

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, {project_id}, opts)
  end

  def init({project_id}) do
    IO.puts("Orchestrator started (#{project_id}).")

    :ok =
      Listener.subscribe(Coflux.ProjectsListener, project_id, self(), [
        Models.Execution,
        Models.Result
      ])

    send(self(), :check_abandoned)
    send(self(), :iterate_sensors)
    {:ok, %State{project_id: project_id}}
  end

  def handle_call(
        {:register_targets, environment_id, repository, version, manifest, pid},
        _from,
        state
      ) do
    _ref = Process.monitor(pid)

    state =
      Enum.reduce(manifest, state, fn {target, _config}, state ->
        put_in(
          state,
          [Access.key(:targets), Access.key({repository, target, environment_id}, %{}), pid],
          version
        )
      end)

    state = try_schedule_executions(state)

    {:reply, :ok, state}
  end

  def handle_call({:get_result, execution_id, pid}, _from, state) do
    # TODO: do this outside the server?
    case get_result(state.project_id, execution_id) do
      {:pending, execution_id} ->
        ref = make_ref()

        state =
          update_in(
            state,
            [Access.key(:waiting), Access.key(execution_id, [])],
            &[{pid, ref} | &1]
          )

        {:reply, {:wait, ref}, state}

      {:resolved, result} ->
        {:reply, {:ok, result}, state}
    end
  end

  def handle_info({:insert, _ref, model}, state) do
    state =
      case model do
        %Models.Execution{} ->
          try_schedule_executions(state)

        %Models.Result{} = result ->
          if result.type in [4, 5] do
            try_abort(state, result.execution_id)
          end

          {_, state} = pop_in(state.executions[result.execution_id])

          try_notify_results(state, result)
      end

    {:noreply, state}
  end

  def handle_info(:check_abandoned, state) do
    now = DateTime.utc_now()

    case Store.list_running_executions(state.project_id) do
      {:ok, executions} ->
        executions
        |> Enum.filter(&execution_abandoned?(&1, now))
        |> Enum.each(fn {execution, _, _} ->
          Store.put_result(state.project_id, execution.id, :abandoned)
        end)

        # TODO: time?
        Process.send_after(self(), :check_abandoned, 1_000)
        {:noreply, state}
    end
  end

  def handle_info(:iterate_sensors, state) do
    case Store.list_pending_sensors(state.project_id) do
      {:ok, sensors} ->
        Enum.each(sensors, fn {activation, iteration, result} ->
          if result do
            # TODO: rate limit
            Store.iterate_sensor(state.project_id, activation, iteration)
          end
        end)

        Process.send_after(self(), :iterate_sensors, 1_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    state =
      state
      |> Map.update!(:targets, fn targets ->
        # TODO: remove target if no pids left
        Map.new(targets, fn {target, pids} -> {target, Map.delete(pids, pid)} end)
      end)
      |> Map.update!(:executions, fn executions ->
        executions
        |> Enum.reject(fn {_, execution_pid} -> execution_pid == pid end)
        |> Map.new()
      end)

    {:noreply, state}
  end

  defp try_schedule_executions(state) do
    case Store.list_pending_executions(state.project_id) do
      {:ok, executions} ->
        Enum.reduce(executions, state, fn execution, state ->
          with {:ok, pid} <- find_agent(state, execution),
               :ok <- Store.assign_execution(state.project_id, execution) do
            send(pid, {:execute, execution.id, execution.target, execution.arguments})
            put_in(state.executions[execution.id], pid)
          else
            :error ->
              state
          end
        end)
    end
  end

  defp find_agent(state, execution) do
    target = {execution.repository, execution.target, execution.environment_id}
    # TODO: filter against version
    with {:ok, pid_map} <- Map.fetch(state.targets, target) do
      {:ok, Enum.random(Map.keys(pid_map))}
    end
  end

  defp try_notify_results(state, result) do
    execution_id = result.execution_id

    Map.update!(state, :waiting, fn waiting ->
      case Map.pop(waiting, execution_id) do
        {nil, waiting} ->
          waiting

        {execution_waiting, waiting} ->
          case get_result(state.project_id, execution_id) do
            {:pending, execution_id} ->
              Map.update(waiting, execution_id, execution_waiting, &(&1 ++ execution_waiting))

            {:resolved, result} ->
              Enum.each(execution_waiting, fn {pid, ref} ->
                send(pid, {:result, ref, result})
              end)

              waiting
          end
      end
    end)
  end

  defp execution_abandoned?({_execution, assignment, latest_heartbeat}, now, timeout_ms \\ 5_000) do
    last_activity_at =
      if latest_heartbeat do
        latest_heartbeat.created_at
      else
        assignment.created_at
      end

    DateTime.diff(now, last_activity_at, :millisecond) > timeout_ms
  end

  defp try_abort(state, execution_id) do
    pid = Map.get(state.executions, execution_id)

    if pid do
      send(pid, {:abort, execution_id})
    end
  end

  defp get_result(project_id, execution_id) do
    case Store.get_result(project_id, execution_id) do
      {:error, :not_found} -> {:pending, execution_id}
      {:ok, {:result, execution_id}} -> get_result(project_id, execution_id)
      {:ok, result} -> {:resolved, result}
    end
  end
end

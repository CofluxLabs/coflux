defmodule Coflux.Orchestration.Server do
  use GenServer, restart: :transient

  alias Coflux.Store

  @abandon_timeout_ms 5_000

  defmodule State do
    defstruct project_id: nil,
              environment: nil,
              db: nil,

              # ref -> session id
              agents: %{},

              # session id -> %{pid, targets}
              sessions: %{},

              # {repository, target} -> [session id]
              targets: %{},

              # ref -> topic
              listeners: %{},

              # topic -> %{ref -> pid}
              topics: %{},

              # execution_id -> [{pid, ref}]
              waiting: %{},

              # execution_id -> timestamp
              running: %{},

              # sensor_activation_id -> execution_id
              sensors: %{}
  end

  def start_link(opts) do
    {project_id, opts} = Keyword.pop!(opts, :project_id)
    {environment, opts} = Keyword.pop!(opts, :environment)
    GenServer.start_link(__MODULE__, {project_id, environment}, opts)
  end

  def init({project_id, environment}) do
    case Store.open(project_id, environment) do
      {:ok, db} ->
        {:ok, pending} = Store.get_pending_assignments(db)

        running =
          Map.new(pending, fn {execution_id, assigned_at, heartbeat_at} ->
            {execution_id, heartbeat_at || assigned_at}
          end)

        {:ok, sensors} = Store.get_activated_sensors(db)

        state = %State{
          project_id: project_id,
          environment: environment,
          db: db,
          running: running,
          sensors: Map.new(sensors)
        }

        send(self(), :check_abandoned)

        {:ok, state}
    end
  end

  def handle_call({:start_session, pid}, _from, state) do
    case Store.start_session(state.db) do
      {:ok, session_id} ->
        ref = Process.monitor(pid)

        state =
          state
          |> put_in([Access.key(:agents), ref], session_id)
          |> put_in([Access.key(:sessions), session_id], %{pid: pid, targets: MapSet.new()})

        {:reply, {:ok, session_id}, state}
    end
  end

  def handle_call({:register_targets, session_id, repository, targets}, _from, state) do
    case Store.get_or_create_manifest(state.db, repository, targets) do
      {:ok, manifest_id} ->
        :ok = Store.record_session_manifest(state.db, session_id, manifest_id)

        state =
          state
          |> register_targets(repository, targets, session_id)
          |> assign_executions()

        notify_listeners(state, :repositories, {:targets, repository, targets})

        # TODO: notify task listeners ({:task, repository, target_name})

        {:reply, :ok, state}
    end
  end

  def handle_call({:schedule_task, repository, target_name, arguments, parent_id}, _from, state) do
    case Store.start_run(state.db, repository, target_name, arguments, parent_id: parent_id) do
      {:ok, run_id, step_id, execution_id, _sequence, created_at} ->
        if parent_id do
          case Store.get_sensor_activation_for_execution_id(state.db, parent_id) do
            {:ok, {sensor_repository, sensor_target}} ->
              target = get_target(state.db, sensor_repository, sensor_target)

              if target.type == :sensor do
                notify_listeners(
                  state,
                  {:sensor, sensor_repository, sensor_target},
                  {:run, run_id, created_at, repository, target_name}
                )
              end

            {:ok, nil} ->
              nil
          end
        end

        notify_listeners(state, {:task, repository, target_name}, {:run, run_id, created_at})

        state = assign_executions(state)
        {:reply, {:ok, run_id, step_id, execution_id}, state}
    end
  end

  def handle_call(
        {:schedule_step, repository, target, arguments, parent_id, cache_key},
        _from,
        state
      ) do
    {:ok, run_id} = Store.get_run_id_for_step_execution(state.db, parent_id)

    case Store.schedule_step(state.db, run_id, parent_id, repository, target, arguments,
           cache_key: cache_key
         ) do
      {:ok, step_id, execution_id, sequence, created_at, cached_execution_id} ->
        notify_listeners(
          state,
          {:run, run_id},
          {:step, step_id, parent_id, repository, target, created_at, arguments,
           cached_execution_id}
        )

        unless cached_execution_id do
          notify_listeners(
            state,
            {:run, run_id},
            {:execution, execution_id, step_id, sequence, created_at}
          )
        end

        state = assign_executions(state)
        {:reply, {:ok, step_id, execution_id || cached_execution_id}, state}
    end
  end

  def handle_call({:rerun_step, step_id}, _from, state) do
    {:ok, run_id} = Store.get_run_id_for_step(state.db, step_id)

    case Store.rerun_step(state.db, step_id) do
      {:ok, execution_id, sequence, created_at} ->
        notify_listeners(
          state,
          {:run, run_id},
          {:execution, execution_id, step_id, sequence, created_at}
        )

        state = assign_executions(state)
        {:reply, {:ok, execution_id, sequence}, state}
    end
  end

  def handle_call({:activate_sensor, repository, target}, _from, state) do
    case Store.activate_sensor(state.db, repository, target) do
      {:ok, sensor_activation_id, _sequence, execution_id} ->
        notify_listeners(state, {:sensor, repository, target}, {:activated, true})

        state =
          state
          |> Map.update!(:sensors, &Map.put(&1, sensor_activation_id, execution_id))
          |> assign_executions()

        {:reply, :ok, state}
    end
  end

  def handle_call({:deactivate_sensor, repository, target}, _from, state) do
    case Store.deactivate_sensor(state.db, repository, target) do
      {:ok, sensor_activation_ids} ->
        notify_listeners(state, {:sensor, repository, target}, {:activated, false})

        sensor_activation_ids
        |> Enum.map(&Map.get(state.sensors, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.each(fn execution_id ->
          # TODO: only send to agent that has execution?
          state.sessions
          |> Map.values()
          |> Enum.each(fn session ->
            send(session.pid, {:abort, execution_id})
          end)
        end)

        {:reply, :ok, state}
    end
  end

  def handle_call({:record_heartbeats, execution_ids}, _from, state) do
    # TODO: check whether any executions have been aborted/abandoned?
    case Store.record_hearbeats(state.db, execution_ids) do
      {:ok, created_at} ->
        state =
          execution_ids
          |> Map.keys()
          |> Enum.reduce(state, fn execution_id, state ->
            put_in(state, [Access.key(:running), execution_id], created_at)
          end)

        {:reply, :ok, state}
    end
  end

  def handle_call({:record_result, execution_id, result}, _from, state) do
    case record_result(state, execution_id, result) do
      {:ok, state} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:record_cursor, execution_id, result}, _from, state) do
    case Store.record_cursor(state.db, execution_id, result) do
      {:ok, _} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_result, execution_id, from_execution_id, pid}, _from, state) do
    if from_execution_id do
      :ok = Store.record_dependency(state.db, from_execution_id, execution_id)
      {:ok, run_id} = Store.get_run_id_for_step_execution(state.db, execution_id)
      notify_listeners(state, {:run, run_id}, {:dependency, from_execution_id, execution_id})
    end

    case resolve_result(execution_id, state.db) do
      {:pending, execution_id} ->
        ref = make_ref()

        state =
          update_in(
            state,
            [Access.key(:waiting), Access.key(execution_id, [])],
            &[{pid, ref} | &1]
          )

        {:reply, {:wait, ref}, state}

      {:ok, result} ->
        {:reply, {:ok, result}, state}
    end
  end

  def handle_call({:subscribe_repositories, pid}, _from, state) do
    {:ok, targets} = Store.get_latest_targets(state.db)
    {:ok, ref, state} = add_listener(state, :repositories, pid)
    {:reply, {:ok, targets, ref}, state}
  end

  def handle_call({:subscribe_task, repository, target_name, pid}, _from, state) do
    target = get_target(state.db, repository, target_name)

    if target && target.type == :task do
      {:ok, runs} = Store.get_task_runs(state.db, repository, target_name)
      {:ok, ref, state} = add_listener(state, {:task, repository, target_name}, pid)
      {:reply, {:ok, target, runs, ref}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:subscribe_sensor, repository, target_name, pid}, _from, state) do
    target = get_target(state.db, repository, target_name)

    if target && target.type == :sensor do
      activated =
        case Store.get_sensor_activation(state.db, repository, target_name) do
          {:ok, {_}} -> true
          {:ok, nil} -> false
        end

      {:ok, executions} = Store.get_sensor_executions(state.db, repository, target_name)
      {:ok, runs} = Store.get_sensor_runs(state.db, repository, target_name)
      {:ok, ref, state} = add_listener(state, {:sensor, repository, target_name}, pid)
      {:reply, {:ok, activated, executions, runs, ref}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:subscribe_run, run_id, pid}, _from, state) do
    {:ok, run} = Store.get_run(state.db, run_id)
    {:ok, steps} = Store.get_run_steps(state.db, run_id)

    steps =
      Map.new(steps, fn {step_id, parent_id, repository, target, created_at, cached_execution_id} ->
        # TODO: skip if cached
        {:ok, executions} = Store.get_step_executions(state.db, step_id)
        {:ok, arguments} = Store.get_step_arguments(state.db, step_id)

        {step_id,
         %{
           repository: repository,
           target: target,
           parent_id: parent_id,
           created_at: created_at,
           cached_execution_id: cached_execution_id,
           arguments: arguments,
           executions:
             Map.new(executions, fn {execution_id, sequence, _execute_after, created_at,
                                     _session_id, assigned_at} ->
               {:ok, dependencies} = Store.get_execution_dependencies(state.db, execution_id)

               {result, completed_at} =
                 case Store.get_execution_result(state.db, execution_id) do
                   {:ok, {result, completed_at}} ->
                     {result, completed_at}

                   {:ok, nil} ->
                     {nil, nil}
                 end

               {execution_id,
                %{
                  sequence: sequence,
                  created_at: created_at,
                  assigned_at: assigned_at,
                  completed_at: completed_at,
                  dependencies: Enum.map(dependencies, fn {dependency_id} -> dependency_id end),
                  result: result
                }}
             end)
         }}
      end)

    {:ok, ref, state} = add_listener(state, {:run, run_id}, pid)
    {:reply, {:ok, run, steps, ref}, state}
  end

  def handle_cast({:unsubscribe, ref}, state) do
    Process.demonitor(ref, [:flush])
    state = remove_listener(state, ref)
    {:noreply, state}
  end

  def handle_info(:check_abandoned, state) do
    state = check_abandoned(state)
    # TODO: only if running executions
    Process.send_after(self(), :check_abandoned, @abandon_timeout_ms)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    cond do
      Map.has_key?(state.agents, ref) ->
        state = unregister_targets(state, ref)
        {:noreply, state}

      Map.has_key?(state.listeners, ref) ->
        state = remove_listener(state, ref)
        {:noreply, state}
    end
  end

  def terminate(_reason, state) do
    Store.close(state.db)
  end

  defp record_result(state, execution_id, result) do
    case Store.record_result(state.db, execution_id, result) do
      {:ok, created_at} ->
        state = Map.update!(state, :running, &Map.delete(&1, execution_id))

        case find_sensor(state, execution_id) do
          nil ->
            state = notify_waiting(state, execution_id)
            {:ok, run_id} = Store.get_run_id_for_step_execution(state.db, execution_id)

            notify_listeners(
              state,
              {:run, run_id},
              {:result, execution_id, 0, result, created_at}
            )

            {:ok, state}

          sensor_activation_id ->
            # TODO: better way to determine whether to iterate?
            if result == :aborted do
              state = Map.update!(state, :sensors, &Map.delete(&1, sensor_activation_id))
              {:ok, state}
            else
              case Store.iterate_sensor(state.db, sensor_activation_id) do
                {:ok, execution_id, _sequence, _created_at} ->
                  state =
                    state
                    |> Map.update!(:sensors, &Map.put(&1, sensor_activation_id, execution_id))
                    |> assign_executions()

                  {:ok, state}
              end
            end
        end
    end
  end

  defp resolve_result(execution_id, db) do
    case Store.get_execution_result(db, execution_id) do
      {:ok, nil} -> {:pending, execution_id}
      {:ok, {{:reference, execution_id}, _}} -> resolve_result(execution_id, db)
      {:ok, {other, _}} -> {:ok, other}
    end
  end

  defp register_targets(state, repository, targets, session_id) do
    targets
    |> Map.keys()
    |> Enum.reduce(state, fn target, state ->
      state
      |> update_in(
        [Access.key(:targets), Access.key({repository, target}, MapSet.new())],
        &MapSet.put(&1, session_id)
      )
      |> update_in(
        [Access.key(:sessions), session_id, :targets],
        &MapSet.put(&1, {repository, target})
      )
    end)
  end

  defp unregister_targets(state, ref) do
    case Map.fetch(state.agents, ref) do
      {:ok, session_id} ->
        session = state.sessions[session_id]

        state
        |> Map.update!(:agents, &Map.delete(&1, ref))
        |> Map.update!(:sessions, &Map.delete(&1, session_id))
        |> Map.update!(:targets, fn targets ->
          Enum.reduce(session.targets, targets, fn target, targets ->
            updated =
              targets
              |> Map.fetch!(target)
              |> MapSet.delete(session_id)

            if Enum.empty?(updated) do
              Map.delete(targets, target)
            else
              Map.put(targets, target, updated)
            end
          end)
        end)
    end
  end

  defp add_listener(state, topic, pid) do
    ref = Process.monitor(pid)

    state =
      state
      |> put_in([Access.key(:listeners), ref], topic)
      |> put_in([Access.key(:topics), Access.key(topic, %{}), ref], pid)

    {:ok, ref, state}
  end

  defp remove_listener(state, ref) do
    case Map.fetch(state.listeners, ref) do
      {:ok, topic} ->
        state
        |> Map.update!(:listeners, &Map.delete(&1, ref))
        |> update_in([Access.key(:topics), topic], &Map.delete(&1, ref))
    end
  end

  defp notify_listeners(state, topic, payload) do
    state.topics
    |> Map.get(topic, %{})
    |> Enum.each(fn {ref, pid} ->
      send(pid, {:topic, ref, payload})
    end)
  end

  defp check_abandoned(state) do
    now = System.os_time(:millisecond)

    Enum.reduce(state.running, state, fn {execution_id, updated_at}, state ->
      if now - updated_at > @abandon_timeout_ms do
        {:ok, state} = record_result(state, execution_id, :abandoned)
        state
      else
        state
      end
    end)
  end

  defp get_target(db, repository, target_name) do
    # TODO: just query specific target
    {:ok, targets} = Store.get_latest_targets(db)
    targets |> Map.get(repository, %{}) |> Map.get(target_name)
  end

  defp find_sensor(state, execution_id) do
    Enum.find_value(state.sensors, fn {sensor_activation_id, e_id} ->
      if e_id == execution_id, do: sensor_activation_id
    end)
  end

  defp assign_execution(state, execution_id, repository, target, arguments_fun) do
    session_ids = Map.get(state.targets, {repository, target}, [])

    if Enum.any?(session_ids) do
      session_id = Enum.random(session_ids)
      session = state.sessions[session_id]

      case arguments_fun.() do
        {:ok, arguments} ->
          {:ok, assigned_at} = Store.assign_execution(state.db, execution_id, session_id)
          state = put_in(state, [Access.key(:running), execution_id], assigned_at)
          send(session.pid, {:execute, execution_id, repository, target, arguments})
          {:ok, state, {session_id, assigned_at}}
      end
    else
      {:ok, state, nil}
    end
  end

  defp assign_executions(state) do
    {:ok, executions} = Store.get_unassigned_executions(state.db)

    Enum.reduce(
      executions,
      state,
      fn
        {execution_id, step_id, nil}, state ->
          {:ok, {run_id, repository, target}} = Store.get_step(state.db, step_id)

          case assign_execution(state, execution_id, repository, target, fn ->
                 Store.get_step_arguments(state.db, step_id)
               end) do
            {:ok, state, nil} ->
              state

            {:ok, state, {session_id, assigned_at}} ->
              # TODO: defer notify?
              notify_listeners(
                state,
                {:run, run_id},
                {:assignment, execution_id, session_id, assigned_at}
              )

              state
          end

        {execution_id, nil, sensor_activation_id}, state ->
          {:ok, {repository, target, deactivated_at}} =
            Store.get_sensor_activation_by_id(state.db, sensor_activation_id)

          if deactivated_at do
            {:ok, state} = record_result(state, execution_id, :aborted)
            state
          else
            case assign_execution(state, execution_id, repository, target, fn ->
                   # TODO: get arguments (from cursor)
                   {:ok, [{:raw, "json", "null"}]}
                 end) do
              {:ok, state, nil} ->
                state

              {:ok, state, {session_id, assigned_at}} ->
                # TODO: defer notify?
                notify_listeners(
                  state,
                  {:sensor, repository, target},
                  {:assignment, execution_id, session_id, assigned_at}
                )

                state
            end
          end
      end
    )

    # TODO: setup timer for next future execution
  end

  defp notify_waiting(state, execution_id) do
    Map.update!(state, :waiting, fn waiting ->
      case Map.pop(waiting, execution_id) do
        {nil, waiting} ->
          waiting

        {execution_waiting, waiting} ->
          case resolve_result(execution_id, state.db) do
            {:pending, execution_id} ->
              Map.update(waiting, execution_id, execution_waiting, &(&1 ++ execution_waiting))

            {:ok, result} ->
              Enum.each(execution_waiting, fn {pid, ref} ->
                send(pid, {:result, ref, result})
              end)

              waiting
          end
      end
    end)
  end
end

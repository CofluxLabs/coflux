defmodule Coflux.Orchestration.Server do
  use GenServer, restart: :transient

  alias Coflux.Orchestration.Store
  alias Coflux.MapUtils

  @session_timeout_ms 5_000
  @recurrent_rate_limit_ms 5_000

  defmodule State do
    defstruct project_id: nil,
              environment: nil,
              db: nil,
              execute_timer: nil,

              # ref -> {pid, session_id}
              agents: %{},

              # session_id -> %{external_id, agent, targets, queue, starting, executing, expire_timer}
              sessions: %{},

              # external_id -> session_id
              session_ids: %{},

              # {repository, target} -> [session_id]
              targets: %{},

              # ref -> topic
              listeners: %{},

              # topic -> %{ref -> pid}
              topics: %{},

              # execution_id -> [{pid, ref}]
              waiting: %{}
  end

  def start_link(opts) do
    {project_id, opts} = Keyword.pop!(opts, :project_id)
    {environment, opts} = Keyword.pop!(opts, :environment)
    GenServer.start_link(__MODULE__, {project_id, environment}, opts)
  end

  def init({project_id, environment}) do
    case Store.open(project_id, environment) do
      {:ok, db} ->
        state = %State{
          project_id: project_id,
          environment: environment,
          db: db
        }

        send(self(), :execute)

        {:ok, state, {:continue, :abandon_pending}}
    end
  end

  def handle_continue(:abandon_pending, state) do
    {:ok, pending} = Store.get_pending_assignments(state.db)

    state =
      Enum.reduce(pending, state, fn {execution_id, _session_id, _assigned_at, _heartbeat_at},
                                     state ->
        {:ok, state} = record_result(state, execution_id, :abandoned)
        state
      end)

    {:noreply, state}
  end

  def handle_call({:connect, external_id, concurrency, pid}, _from, state) do
    if external_id do
      case Map.fetch(state.session_ids, external_id) do
        {:ok, session_id} ->
          session = Map.fetch!(state.sessions, session_id)

          if session.expire_timer do
            Process.cancel_timer(session.expire_timer)
          end

          state =
            if session.agent do
              {{pid, ^session_id}, state} = pop_in(state.agents[session.agent])
              # TODO: better reason?
              Process.exit(pid, :kill)
              state
            else
              state
            end

          ref = Process.monitor(pid)

          state.sessions[session_id].queue
          |> Enum.reverse()
          |> Enum.each(&send(pid, &1))

          state =
            state
            |> put_in([Access.key(:agents), ref], {pid, session_id})
            |> update_in(
              [Access.key(:sessions), session_id],
              &Map.merge(&1, %{
                agent: ref,
                queue: [],
                concurrency: concurrency
              })
            )

          notify_agent(state, session_id)

          {:reply, {:ok, external_id}, state}

        :error ->
          {:reply, {:error, :no_session}, state}
      end
    else
      case Store.start_session(state.db) do
        {:ok, session_id, external_id} ->
          ref = Process.monitor(pid)

          session =
            external_id
            |> build_session()
            |> Map.put(:agent, ref)
            |> Map.put(:concurrency, concurrency)

          state =
            state
            |> put_in([Access.key(:agents), ref], {pid, session_id})
            |> put_in([Access.key(:sessions), session_id], session)
            |> put_in([Access.key(:session_ids), external_id], session_id)

          notify_agent(state, session_id)

          {:reply, {:ok, external_id}, state}
      end
    end
  end

  def handle_call({:register_targets, external_session_id, repository, targets}, _from, state) do
    session_id = Map.fetch!(state.session_ids, external_session_id)

    case Store.get_or_create_manifest(state.db, repository, targets) do
      {:ok, manifest_id} ->
        :ok = Store.record_session_manifest(state.db, session_id, manifest_id)
        state = register_targets(state, repository, targets, session_id)
        notify_listeners(state, :repositories, {:targets, repository, targets})
        notify_agent(state, session_id)

        Enum.each(targets, fn {target_name, target} ->
          notify_listeners(
            state,
            {:target, repository, target_name},
            {:target, target.type, target.parameters}
          )
        end)

        send(self(), :execute)
        {:reply, :ok, state}
    end
  end

  def handle_call(
        {:schedule, repository, target_name, arguments, opts},
        _from,
        state
      ) do
    target = get_target(state.db, repository, target_name)

    # TODO: handle unrecognised target (return {:error, :invalid_target}?)

    opts = Keyword.put(opts, :recurrent, target.type == :sensor)

    result =
      case Keyword.get(opts, :parent_id) do
        nil ->
          if target.type in [:task, :sensor] do
            start_run(state, repository, target_name, arguments, opts)
          else
            {:error, :invalid_target}
          end

        parent_id ->
          {:ok, step} = Store.get_step_for_execution(state.db, parent_id)

          case target.type do
            :task ->
              start_run(
                state,
                repository,
                target_name,
                arguments,
                opts,
                {step.run_id, parent_id}
              )

            :step ->
              schedule_step(
                state,
                step.run_id,
                parent_id,
                repository,
                target_name,
                arguments,
                opts
              )

            _ ->
              {:error, :invalid_target}
          end
      end

    case result do
      {:ok, external_run_id, external_step_id, execution_id, state} ->
        {:reply, {:ok, external_run_id, external_step_id, execution_id}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:cancel_run, external_run_id}, _from, state) do
    # TODO: use one query to get all execution ids?
    case Store.get_run_by_external_id(state.db, external_run_id) do
      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      {:ok, run} ->
        {:ok, steps} = Store.get_run_steps(state.db, run.id)

        state =
          Enum.reduce(steps, state, fn step, state ->
            {step_id, _, _, repository, _, _, _} = step

            {:ok, executions} = Store.get_step_executions(state.db, step_id)
            execution_ids = Enum.map(executions, &elem(&1, 0))

            Enum.reduce(execution_ids, state, fn execution_id, state ->
              state = abort_execution(state, execution_id)

              case Store.get_execution_result(state.db, execution_id) do
                {:ok, nil} ->
                  case record_and_notify_result(
                         state,
                         execution_id,
                         :cancelled,
                         run.id,
                         repository
                       ) do
                    {:ok, state} -> state
                    {:error, :already_recorded} -> state
                  end

                {:ok, _other} ->
                  state
              end
            end)
          end)

        {:reply, :ok, state}
    end
  end

  def handle_call({:rerun_step, external_step_id}, _from, state) do
    {:ok, step} = Store.get_step_by_external_id(state.db, external_step_id)
    # TODO: abort/cancel any running/scheduled retry? (and reference this retry?)
    {:ok, execution_id, sequence, state} = rerun_step(state, step)
    {:reply, {:ok, execution_id, sequence}, state}
  end

  def handle_call({:record_heartbeats, executions, external_session_id}, _from, state) do
    # TODO: handle execution statuses?
    session_id = Map.fetch!(state.session_ids, external_session_id)
    session = Map.fetch!(state.sessions, session_id)

    execution_ids = executions |> Map.keys() |> MapSet.new()

    state =
      session.starting
      |> MapSet.intersection(execution_ids)
      |> Enum.reduce(state, fn execution_id, state ->
        update_in(state.sessions[session_id].starting, &MapSet.delete(&1, execution_id))
      end)

    state =
      session.executing
      |> MapSet.difference(execution_ids)
      |> Enum.reduce(state, fn execution_id, state ->
        case Store.get_execution_result(state.db, execution_id) do
          {:ok, nil} ->
            {:ok, state} = record_result(state, execution_id, :abandoned)
            state

          {:ok, _other} ->
            state
        end
      end)

    state =
      execution_ids
      |> MapSet.difference(session.starting)
      |> MapSet.difference(session.executing)
      |> Enum.reduce(state, fn execution_id, state ->
        case Store.get_execution_result(state.db, execution_id) do
          {:ok, nil} ->
            state

          {:ok, _other} ->
            send_session(state, session_id, {:abort, execution_id})
        end
      end)

    case Store.record_hearbeats(state.db, executions) do
      {:ok, _created_at} ->
        state = put_in(state.sessions[session_id].executing, execution_ids)
        {:reply, :ok, state}
    end
  end

  def handle_call({:notify_terminated, execution_ids}, _from, state) do
    # TODO: record in database?

    state =
      Enum.reduce(execution_ids, state, fn execution_id, state ->
        case find_session_for_execution(state, execution_id) do
          {:ok, session_id} ->
            update_in(state.sessions[session_id], fn session ->
              session
              |> Map.update!(:starting, &MapSet.delete(&1, execution_id))
              |> Map.update!(:executing, &MapSet.delete(&1, execution_id))
            end)

          :error ->
            state
        end
      end)

    {:reply, :ok, state}
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
      {:ok, step} = Store.get_step_for_execution(state.db, from_execution_id)

      notify_listeners(
        state,
        {:run, step.run_id},
        {:dependency, from_execution_id, execution_id}
      )
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

    executing =
      state.sessions
      |> Map.values()
      |> Enum.reduce(MapSet.new(), fn session, executing ->
        executing |> MapSet.union(session.executing) |> MapSet.union(session.starting)
      end)

    {:ok, executions} = Store.get_unassigned_executions(state.db)

    executions =
      Enum.reduce(executions, %{}, fn execution, executions ->
        {execution_id, _, _, repository, _, _, execute_after, created_at} = execution
        default = %{executing: MapSet.new(), scheduled: %{}}

        if Enum.member?(executing, execution_id) do
          put_in(
            executions,
            [Access.key(repository, default), :scheduled, execution_id],
            execute_after || created_at
          )
        else
          put_in(
            executions,
            [Access.key(repository, default), :executing],
            execution_id
          )
        end
      end)

    {:ok, ref, state} = add_listener(state, :repositories, pid)

    {:reply, {:ok, targets, executions, ref}, state}
  end

  def handle_call({:subscribe_agents, pid}, _from, state) do
    agents =
      Map.new(state.agents, fn {_, {_, session_id}} ->
        session = Map.fetch!(state.sessions, session_id)
        {session_id, session.targets}
      end)

    {:ok, ref, state} = add_listener(state, :agents, pid)
    {:reply, {:ok, agents, ref}, state}
  end

  def handle_call({:subscribe_target, repository, target_name, pid}, _from, state) do
    target = get_target(state.db, repository, target_name)

    if target && target.type in [:task, :sensor] do
      {:ok, runs} = Store.get_target_runs(state.db, repository, target_name)
      {:ok, ref, state} = add_listener(state, {:target, repository, target_name}, pid)
      {:reply, {:ok, target, runs, ref}, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:subscribe_run, external_run_id, pid}, _from, state) do
    case Store.get_run_by_external_id(state.db, external_run_id) do
      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      {:ok, run} ->
        {:ok, parent} =
          if run.parent_id do
            # TODO: use `resolve_execution`?
            Store.get_run_by_execution(state.db, run.parent_id)
          else
            {:ok, nil}
          end

        {:ok, steps} = Store.get_run_steps(state.db, run.id)

        steps =
          Map.new(steps, fn {step_id, step_external_id, parent_id, repository, target, created_at,
                             cached_execution_id} ->
            # TODO: skip if cached
            {:ok, executions} = Store.get_step_executions(state.db, step_id)
            {:ok, arguments} = Store.get_step_arguments(state.db, step_id)

            {step_external_id,
             %{
               repository: repository,
               target: target,
               parent_id: parent_id,
               created_at: created_at,
               cached_execution_id: cached_execution_id,
               arguments: arguments,
               executions:
                 Map.new(executions, fn {execution_id, sequence, execute_after, created_at,
                                         _session_id, assigned_at} ->
                   {:ok, dependencies} = Store.get_execution_dependencies(state.db, execution_id)

                   dependencies =
                     Enum.map(dependencies, fn {dependency_id} ->
                       # TODO: if execution doesn't belong to this run, resolve it (`resolve_execution`)
                       # TODO: (and where event is fired)
                       # TODO: or update `get_execution_dependencies` to do resolving?
                       dependency_id
                     end)

                   {result, retry_id, completed_at} =
                     case Store.get_execution_result(state.db, execution_id) do
                       {:ok, {result, retry_id, completed_at}} ->
                         {result, retry_id, completed_at}

                       {:ok, nil} ->
                         {nil, nil, nil}
                     end

                   retry =
                     if retry_id do
                       resolve_execution(state.db, retry_id)
                     end

                   {:ok, children} = Store.get_runs_by_parent(state.db, execution_id)

                   {execution_id,
                    %{
                      sequence: sequence,
                      created_at: created_at,
                      execute_after: execute_after,
                      assigned_at: assigned_at,
                      completed_at: completed_at,
                      dependencies: dependencies,
                      result: result,
                      children: children,
                      retry: retry
                    }}
                 end)
             }}
          end)

        {:ok, ref, state} = add_listener(state, {:run, run.id}, pid)
        {:reply, {:ok, run, parent, steps, ref}, state}
    end
  end

  def handle_call({:lookup_runs, execution_ids}, _from, state) do
    result =
      Map.new(execution_ids, fn execution_id ->
        {:ok, {external_id}} = Store.get_external_run_id_for_execution(state.db, execution_id)
        {execution_id, external_id}
      end)

    {:reply, result, state}
  end

  def handle_cast({:unsubscribe, ref}, state) do
    Process.demonitor(ref, [:flush])
    state = remove_listener(state, ref)
    {:noreply, state}
  end

  def handle_info({:expire_session, session_id}, state) do
    if state.sessions[session_id].agent do
      IO.puts("Ignoring session expire (#{inspect(session_id)})")
      {:noreply, state}
    else
      {session, state} = pop_in(state.sessions[session_id])

      state =
        session.executing
        |> MapSet.union(session.starting)
        |> Enum.reduce(state, fn execution_id, state ->
          {:ok, state} = record_result(state, execution_id, :abandoned)
          state
        end)
        |> Map.update!(:targets, fn all_targets ->
          Enum.reduce(
            session.targets,
            all_targets,
            fn {repository, repository_targets}, all_targets ->
              Enum.reduce(repository_targets, all_targets, fn target, all_targets ->
                MapUtils.delete_in(all_targets, [repository, target, session_id])
              end)
            end
          )
        end)
        |> Map.update!(:session_ids, &Map.delete(&1, session.external_id))

      {:noreply, state}
    end
  end

  def handle_info(:execute, state) do
    state =
      if state.execute_timer do
        Process.cancel_timer(state.execute_timer)
        Map.put(state, :execute_timer, nil)
      else
        state
      end

    {:ok, executions} = Store.get_unassigned_executions(state.db)
    now = System.os_time(:millisecond)

    {executions_due, executions_future, executions_duplicated} =
      split_executions(executions, now)

    state =
      executions_duplicated
      |> Enum.reverse()
      |> Enum.reduce(state, fn {execution_id, duplication_id, run_id, repository}, state ->
        case record_and_notify_result(
               state,
               execution_id,
               :duplicated,
               run_id,
               repository,
               duplication_id
             ) do
          {:ok, state} -> state
          {:error, :already_recorded} -> state
        end
      end)

    {state, assigned, _unassigned} =
      executions_due
      |> Enum.reverse()
      |> Enum.reduce(
        {state, %{}, []},
        fn
          execution, {state, assigned, unassigned} ->
            {execution_id, step_id, run_id, repository, target, _, _, _} = execution

            case assign_execution(state, execution_id, repository, target, fn ->
                   Store.get_step_arguments(state.db, step_id)
                 end) do
              {:ok, state, {_session_id, assigned_at}} ->
                # TODO: defer notify?
                notify_listeners(
                  state,
                  {:run, run_id},
                  {:assignment, execution_id, assigned_at}
                )

                assigned =
                  assigned
                  |> Map.put_new(repository, MapSet.new())
                  |> Map.update!(repository, &MapSet.put(&1, execution_id))

                {state, assigned, unassigned}

              {:error, :no_session} ->
                {state, assigned, [execution | unassigned]}
            end
        end
      )

    notify_listeners(state, :repositories, {:assigned, assigned})

    next_execute_after =
      executions_future
      |> Enum.map(&elem(&1, 6))
      |> Enum.min(fn -> nil end)

    state =
      if next_execute_after do
        delay_ms = trunc(next_execute_after) - System.os_time(:millisecond)

        if delay_ms > 0 do
          timer = Process.send_after(self(), :execute, delay_ms)
          Map.put(state, :execute_timer, timer)
        else
          send(self(), :execute)
          state
        end
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    cond do
      Map.has_key?(state.agents, ref) ->
        {{^pid, session_id}, state} = pop_in(state.agents[ref])

        # TODO: (re-)schedule timer when receiving heartbeats?
        expire_timer =
          Process.send_after(self(), {:expire_session, session_id}, @session_timeout_ms)

        state =
          update_in(
            state.sessions[session_id],
            &Map.merge(&1, %{agent: nil, expire_timer: expire_timer})
          )

        notify_agent(state, session_id)

        {:noreply, state}

      Map.has_key?(state.listeners, ref) ->
        state = remove_listener(state, ref)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  def terminate(_reason, state) do
    Store.close(state.db)
  end

  defp build_session(external_id) do
    %{
      external_id: external_id,
      agent: nil,
      targets: %{},
      queue: [],
      starting: MapSet.new(),
      executing: MapSet.new(),
      expire_timer: nil,
      concurrency: 0
    }
  end

  defp split_executions(executions, now) do
    {executions_due, executions_future, executions_duplicated, _} =
      executions
      |> Enum.reverse()
      |> Enum.reduce(
        {[], [], [], %{}},
        fn execution, {due, future, duplicated, duplications} ->
          {execution_id, _, run_id, repository, target, duplication_key, execute_after, _} =
            execution

          duplication_key = duplication_key && {repository, target, duplication_key}
          duplication_id = duplication_key && Map.get(duplications, duplication_key)

          if duplication_id do
            {due, future, [{execution_id, duplication_id, run_id, repository} | duplicated],
             duplications}
          else
            duplications =
              if duplication_key do
                Map.put(duplications, duplication_key, execution_id)
              else
                duplications
              end

            if is_nil(execute_after) || execute_after <= now do
              {[execution | due], future, duplicated, duplications}
            else
              {due, [execution | future], duplicated, duplications}
            end
          end
        end
      )

    {executions_due, executions_future, executions_duplicated}
  end

  defp rerun_step(state, step, execute_after \\ nil) do
    case Store.rerun_step(state.db, step.id, execute_after) do
      {:ok, execution_id, sequence, created_at} ->
        notify_listeners(
          state,
          {:run, step.run_id},
          {:execution, execution_id, step.external_id, sequence, created_at, execute_after}
        )

        send(self(), :execute)
        {:ok, execution_id, sequence, state}
    end
  end

  defp result_retryable?(result) do
    case result do
      {:error, _, _} -> true
      :abandoned -> true
      _ -> false
    end
  end

  defp resolve_execution(db, execution_id) do
    {:ok, {external_run_id, external_step_id, step_sequence, _, _}} =
      Store.get_run_by_execution(db, execution_id)

    %{
      run_id: external_run_id,
      step_id: external_step_id,
      sequence: step_sequence
    }
  end

  defp record_and_notify_result(state, execution_id, result, run_id, repository, retry_id \\ nil) do
    case Store.record_result(state.db, execution_id, result, retry_id) do
      {:ok, created_at} ->
        state = notify_waiting(state, execution_id)

        retry =
          if retry_id do
            resolve_execution(state.db, retry_id)
          end

        notify_listeners(
          state,
          {:run, run_id},
          {:result, execution_id, result, retry, created_at}
        )

        notify_listeners(state, :repositories, {:completed, repository, execution_id})

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_result(state, execution_id, result) do
    {:ok, step} = Store.get_step_for_execution(state.db, execution_id)

    {retry_id, state} =
      if result_retryable?(result) && step.retry_count > 0 do
        {:ok, executions} = Store.get_step_executions(state.db, step.id)

        attempts = Enum.count(executions)

        if attempts <= step.retry_count do
          # TODO: add jitter (within min/max delay)
          delay_s =
            step.retry_delay_min +
              (attempts - 1) / (step.retry_count - 1) *
                (step.retry_delay_max - step.retry_delay_min)

          execute_after = System.os_time(:millisecond) + delay_s * 1000
          {:ok, retry_id, _, state} = rerun_step(state, step, execute_after)
          {retry_id, state}
        else
          {nil, state}
        end
      else
        if is_nil(step.parent_id) do
          {:ok, run} = Store.get_run_by_id(state.db, step.run_id)

          if run.recurrent do
            {:ok, executions} = Store.get_step_executions(state.db, step.id)

            if Enum.all?(executions, &elem(&1, 5)) do
              now = System.os_time(:millisecond)

              last_assigned_at =
                executions |> Enum.map(&elem(&1, 5)) |> Enum.max(&>=/2, fn -> nil end)

              execute_after =
                if last_assigned_at && now - last_assigned_at < @recurrent_rate_limit_ms do
                  last_assigned_at + @recurrent_rate_limit_ms
                end

              {:ok, retry_id, _, state} = rerun_step(state, step, execute_after)
              {retry_id, state}
            else
              {nil, state}
            end
          else
            {nil, state}
          end
        else
          {nil, state}
        end
      end

    state =
      case record_and_notify_result(
             state,
             execution_id,
             result,
             step.run_id,
             step.repository,
             retry_id
           ) do
        {:ok, state} -> state
        {:error, :already_recorded} -> state
      end

    {:ok, state}
  end

  defp resolve_result(execution_id, db) do
    # TODO: check execution exists?
    case Store.get_execution_result(db, execution_id) do
      {:ok, nil} ->
        {:pending, execution_id}

      {:ok, {_, retry_id, _}} when not is_nil(retry_id) ->
        resolve_result(retry_id, db)

      {:ok, {{:reference, execution_id}, nil, _}} ->
        resolve_result(execution_id, db)

      {:ok, {other, nil, _}} ->
        {:ok, other}
    end
  end

  defp register_targets(state, repository, targets, session_id) do
    targets
    |> Map.keys()
    |> Enum.reduce(state, fn target, state ->
      state
      |> update_in(
        [Access.key(:targets), Access.key(repository, %{}), Access.key(target, MapSet.new())],
        &MapSet.put(&1, session_id)
      )
      |> update_in(
        [Access.key(:sessions), session_id, :targets, Access.key(repository, MapSet.new())],
        &MapSet.put(&1, target)
      )
    end)
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
        |> Map.update!(:topics, fn topics ->
          MapUtils.delete_in(topics, [topic, ref])
        end)
    end
  end

  defp notify_listeners(state, topic, payload) do
    state.topics
    |> Map.get(topic, %{})
    |> Enum.each(fn {ref, pid} ->
      send(pid, {:topic, ref, payload})
    end)
  end

  defp notify_agent(state, session_id) do
    session = Map.fetch!(state.sessions, session_id)
    targets = if session.agent, do: session.targets
    notify_listeners(state, :agents, {:agent, session_id, targets})
  end

  defp send_session(state, session_id, message) do
    session = state.sessions[session_id]

    if session.agent do
      {pid, ^session_id} = state.agents[session.agent]
      send(pid, message)
      state
    else
      update_in(state.sessions[session_id].queue, &[message | &1])
    end
  end

  defp start_run(state, repository, target_name, arguments, opts, parent \\ nil) do
    case Store.start_run(state.db, repository, target_name, arguments, opts) do
      {:ok, _run_id, external_run_id, _step_id, external_step_id, execution_id, _sequence,
       created_at, is_cached} ->
        if parent do
          {run_id, parent_id} = parent

          notify_listeners(
            state,
            {:run, run_id},
            {:child, parent_id, external_run_id, created_at, repository, target_name,
             execution_id}
          )
        end

        notify_listeners(
          state,
          {:target, repository, target_name},
          {:run, external_run_id, created_at}
        )

        unless is_cached do
          # TODO: neater way to get execution time?
          execute_at = Keyword.get(opts, :execute_after) || created_at

          notify_listeners(
            state,
            :repositories,
            {:scheduled, repository, execution_id, execute_at}
          )
        end

        send(self(), :execute)

        {:ok, external_run_id, external_step_id, execution_id, state}
    end
  end

  defp schedule_step(state, run_id, parent_id, repository, target_name, arguments, opts) do
    case Store.schedule_step(
           state.db,
           run_id,
           parent_id,
           repository,
           target_name,
           arguments,
           opts
         ) do
      {:ok, _step_id, external_step_id, execution_id, sequence, created_at, is_cached} ->
        cached_execution_id = if is_cached, do: execution_id

        notify_listeners(
          state,
          {:run, run_id},
          {:step, external_step_id, parent_id, repository, target_name, created_at, arguments,
           cached_execution_id}
        )

        unless is_cached do
          execute_after = Keyword.get(opts, :execute_after)

          notify_listeners(
            state,
            {:run, run_id},
            {:execution, execution_id, external_step_id, sequence, created_at, execute_after}
          )

          execute_at = execute_after || created_at

          notify_listeners(
            state,
            :repositories,
            {:scheduled, repository, execution_id, execute_at}
          )
        end

        send(self(), :execute)

        # TODO: return (external) run id?
        {:ok, nil, external_step_id, execution_id, state}
    end
  end

  defp get_target(db, repository, target_name) do
    # TODO: just query specific target
    {:ok, targets} = Store.get_latest_targets(db)
    targets |> Map.get(repository, %{}) |> Map.get(target_name)
  end

  defp session_at_capacity(state, session_id) do
    session = state.sessions[session_id]

    if session.concurrency != 0 do
      load = MapSet.size(session.starting) + MapSet.size(session.executing)
      load >= session.concurrency
    else
      false
    end
  end

  defp assign_execution(state, execution_id, repository, target, arguments_fun) do
    session_ids =
      state.targets
      |> Map.get(repository, %{})
      |> Map.get(target, MapSet.new())
      |> Enum.reject(&session_at_capacity(state, &1))

    if Enum.any?(session_ids) do
      session_id = Enum.random(session_ids)

      case arguments_fun.() do
        {:ok, arguments} ->
          {:ok, assigned_at} = Store.assign_execution(state.db, execution_id, session_id)

          state =
            state
            |> update_in(
              [Access.key(:sessions), session_id, :starting],
              &MapSet.put(&1, execution_id)
            )
            |> send_session(
              session_id,
              {:execute, execution_id, repository, target, arguments}
            )

          {:ok, state, {session_id, assigned_at}}
      end
    else
      {:error, :no_session}
    end
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

  defp find_session_for_execution(state, execution_id) do
    state.sessions
    |> Map.keys()
    |> Enum.find(fn session_id ->
      session = Map.fetch!(state.sessions, session_id)

      MapSet.member?(session.starting, execution_id) or
        MapSet.member?(session.executing, execution_id)
    end)
    |> case do
      nil -> :error
      session_id -> {:ok, session_id}
    end
  end

  defp abort_execution(state, execution_id) do
    case find_session_for_execution(state, execution_id) do
      {:ok, session_id} ->
        send_session(state, session_id, {:abort, execution_id})

      :error ->
        IO.puts("Couldn't locate session for execution #{execution_id}. Ignoring.")
        state
    end
  end
end

defmodule Coflux.Orchestration.Server do
  use GenServer, restart: :transient

  alias Coflux.Store
  alias Coflux.MapUtils
  alias Coflux.Orchestration.{Sessions, Runs, Results}

  @session_timeout_ms 5_000
  @recurrent_rate_limit_ms 5_000

  defmodule State do
    defstruct project_id: nil,
              db: nil,
              execute_timer: nil,

              # ref -> {pid, session_id}
              agents: %{},

              # session_id -> %{external_id, agent, targets, queue, starting, executing, expire_timer, concurrency, environment_id}
              sessions: %{},

              # external_id -> session_id
              session_ids: %{},

              # {repository, target} -> [session_id]
              targets: %{},

              # ref -> topic
              listeners: %{},

              # topic -> %{ref -> pid}
              topics: %{},

              # topic -> [notification]
              notifications: %{},

              # execution_id -> [{session_id, request_id}]
              waiting: %{}
  end

  def start_link(opts) do
    {project_id, opts} = Keyword.pop!(opts, :project_id)
    GenServer.start_link(__MODULE__, project_id, opts)
  end

  def init(project_id) do
    case Store.open(project_id, "orchestration") do
      {:ok, db} ->
        state = %State{
          project_id: project_id,
          db: db
        }

        send(self(), :execute)

        {:ok, state, {:continue, :abandon_pending}}
    end
  end

  def handle_continue(:abandon_pending, state) do
    {:ok, pending} = Runs.get_pending_assignments(state.db)

    state =
      Enum.reduce(pending, state, fn {execution_id}, state ->
        {:ok, state} = record_result(state, execution_id, :abandoned)
        state
      end)

    {:noreply, state}
  end

  def handle_call({:create_environment, name, base_name}, _from, state) do
    case Sessions.create_environment(state.db, name, base_name) do
      {:ok, _} ->
        state =
          state
          |> notify_listeners(:project, {:environment_created, name, %{base: base_name}})
          |> flush_notifications()

        {:reply, :ok, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:connect, external_session_id, environment, concurrency, pid}, _from, state) do
    result =
      if external_session_id do
        # TODO: check environment matches existing session
        case Map.fetch(state.session_ids, external_session_id) do
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
              |> notify_agent(session_id)

            executions =
              session.executing
              |> MapSet.union(session.starting)
              |> Map.new(fn execution_id ->
                # TODO: more efficient way to load run IDs?
                {:ok, external_run_id} =
                  Runs.get_external_run_id_for_execution(state.db, execution_id)

                {execution_id, external_run_id}
              end)

            send(self(), :execute)

            {:ok, external_session_id, executions, state}

          :error ->
            {:error, :no_session}
        end
      else
        case Sessions.start_session(state.db, environment) do
          {:ok, session_id, external_session_id, environment_id} ->
            ref = Process.monitor(pid)

            session =
              external_session_id
              |> build_session()
              |> Map.put(:agent, ref)
              |> Map.put(:concurrency, concurrency)
              |> Map.put(:environment_id, environment_id)

            state =
              state
              |> put_in([Access.key(:agents), ref], {pid, session_id})
              |> put_in([Access.key(:sessions), session_id], session)
              |> put_in([Access.key(:session_ids), external_session_id], session_id)
              |> notify_agent(session_id)

            {:ok, external_session_id, %{}, state}

          {:error, :environment_invalid} ->
            {:error, :environment_invalid}
        end
      end

    case result do
      {:ok, external_session_id, executions, state} ->
        state = flush_notifications(state)
        {:reply, {:ok, external_session_id, executions}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:register_targets, external_session_id, repository, targets}, _from, state) do
    session_id = Map.fetch!(state.session_ids, external_session_id)

    case Sessions.get_or_create_manifest(state.db, repository, targets) do
      {:ok, manifest_id} ->
        :ok = Sessions.record_session_manifest(state.db, session_id, manifest_id)
        environment_id = state.sessions[session_id].environment_id

        state =
          state
          |> register_targets(repository, targets, session_id)
          |> notify_listeners(
            {{:repositories, environment_id}, environment_id},
            {:targets, repository, targets}
          )
          |> notify_agent(session_id)

        state =
          targets
          |> Enum.reduce(state, fn {target_name, target}, state ->
            notify_listeners(
              state,
              {:target, repository, target_name, environment_id},
              {:target, target.type, target.parameters}
            )
          end)
          |> flush_notifications()

        send(self(), :execute)

        {:reply, :ok, state}
    end
  end

  def handle_call(
        {:schedule, repository, target_name, arguments, opts},
        _from,
        state
      ) do
    {:ok, parent} =
      case Keyword.get(opts, :parent_id) do
        nil ->
          {:ok, nil}

        parent_id ->
          {:ok, step} = Runs.get_step_for_execution(state.db, parent_id)
          {:ok, {step.run_id, parent_id}}
      end

    {:ok, environment_id} =
      case parent do
        {_run_id, parent_id} ->
          Runs.get_environment_for_execution(state.db, parent_id)

        nil ->
          environment_name = Keyword.get(opts, :environment)
          # TODO: handle error
          {:ok, {environment_id}} = Sessions.get_environment_by_name(state.db, environment_name)
          {:ok, environment_id}
      end

    # TODO: don't require recognised target?
    {:ok, target} = Sessions.get_target(state.db, repository, target_name, environment_id)

    if target do
      opts = Keyword.put(opts, :recurrent, target.type == :sensor)

      {result, state} =
        case parent do
          nil ->
            if target.type in [:workflow, :sensor] do
              start_run(state, repository, target_name, arguments, environment_id, opts)
            else
              {{:error, :invalid_target}, state}
            end

          {parent_run_id, parent_id} ->
            case target.type do
              :workflow ->
                start_run(
                  state,
                  repository,
                  target_name,
                  arguments,
                  environment_id,
                  opts,
                  {parent_run_id, parent_id}
                )

              :task ->
                schedule_step(
                  state,
                  parent_run_id,
                  parent_id,
                  repository,
                  target_name,
                  arguments,
                  environment_id,
                  opts
                )

              _ ->
                {{:error, :invalid_target}, state}
            end
        end

      state = flush_notifications(state)

      {:reply, result, state}
    else
      {:reply, {:error, :invalid_target}, state}
    end
  end

  def handle_call({:cancel_run, external_run_id}, _from, state) do
    # TODO: use one query to get all execution ids?
    case Runs.get_run_by_external_id(state.db, external_run_id) do
      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      {:ok, run} ->
        {:ok, executions} = Runs.get_run_executions(state.db, run.id)

        state =
          Enum.reduce(executions, state, fn {execution_id, repository, assigned_at, completed_at},
                                            state ->
            if !completed_at do
              state =
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

              if assigned_at do
                abort_execution(state, execution_id)
              else
                state
              end
            else
              state
            end
          end)

        state = flush_notifications(state)

        {:reply, :ok, state}
    end
  end

  # TODO: specify execution (by attempt?) instead of step (and then check that environment is a descendent of (or same as) the original)
  def handle_call({:rerun_step, external_step_id, environment_name}, _from, state) do
    {:ok, step} = Runs.get_step_by_external_id(state.db, external_step_id)

    # TODO: abort/cancel any running/scheduled retry? (for the same environment) (and reference this retry?)
    case Sessions.get_environment_by_name(state.db, environment_name) do
      {:ok, nil} ->
        {:reply, {:error, :environment_invalid}, state}

      {:ok, {environment_id}} ->
        {:ok, execution_id, attempt, state} = rerun_step(state, step, environment_id, nil)
        state = flush_notifications(state)
        {:reply, {:ok, execution_id, attempt}, state}
    end
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
        case Results.has_result?(state.db, execution_id) do
          {:ok, false} ->
            {:ok, state} = record_result(state, execution_id, :abandoned)
            state

          {:ok, true} ->
            state
        end
      end)

    # TODO: notify agent (so it can remove executions)?
    state =
      execution_ids
      |> MapSet.difference(session.starting)
      |> MapSet.difference(session.executing)
      |> Enum.reduce(state, fn execution_id, state ->
        case Results.has_result?(state.db, execution_id) do
          {:ok, false} ->
            state

          {:ok, true} ->
            send_session(state, session_id, {:abort, execution_id})
        end
      end)

    case Runs.record_hearbeats(state.db, executions) do
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

    send(self(), :execute)

    {:reply, :ok, state}
  end

  def handle_call({:record_checkpoint, execution_id, arguments}, _from, state) do
    case Results.record_checkpoint(state.db, execution_id, arguments) do
      {:ok, _checkpoint_id, _attempt, _created_at} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:record_result, execution_id, result}, _from, state) do
    case record_result(state, execution_id, result) do
      {:ok, state} ->
        state = flush_notifications(state)
        {:reply, :ok, state}
    end
  end

  def handle_call(
        {:get_result, execution_id, from_execution_id, external_session_id, request_id},
        _from,
        state
      ) do
    # TODO: check execution_id exists? (call resolve_result first?)

    state =
      if from_execution_id do
        {:ok, id} = Runs.record_result_dependency(state.db, from_execution_id, execution_id)

        if id do
          {:ok, step} = Runs.get_step_for_execution(state.db, from_execution_id)

          # TODO: only resolve if there are listeners to notify
          dependency = resolve_execution(state.db, execution_id)

          notify_listeners(
            state,
            {:run, step.run_id},
            {:result_dependency, from_execution_id, execution_id, dependency}
          )
        else
          state
        end
      else
        state
      end

    {result, state} =
      case resolve_result(execution_id, state.db) do
        {:pending, execution_id} ->
          session_id = Map.fetch!(state.session_ids, external_session_id)

          state =
            update_in(
              state,
              [Access.key(:waiting), Access.key(execution_id, [])],
              &[{session_id, request_id} | &1]
            )

          {:wait, state}

        {:ok, result} ->
          {{:ok, result}, state}
      end

    state = flush_notifications(state)

    {:reply, result, state}
  end

  def handle_call({:put_asset, execution_id, type, path, blob_key, metadata}, _from, state) do
    {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)
    {:ok, asset_id} = Results.create_asset(state.db, execution_id, type, path, blob_key, metadata)
    asset = resolve_asset(state.db, asset_id, false)
    state = notify_listeners(state, {:run, step.run_id}, {:asset, execution_id, asset_id, asset})
    {:reply, {:ok, asset_id}, state}
  end

  def handle_call({:get_asset, asset_id, from_execution_id}, _from, state) do
    case Results.get_asset_by_id(state.db, asset_id, false) do
      {:ok, {asset_execution_id, type, path, blob_key, _, _}} ->
        state =
          if from_execution_id do
            {:ok, id} = Runs.record_asset_dependency(state.db, from_execution_id, asset_id)

            if id do
              {:ok, step} = Runs.get_step_for_execution(state.db, from_execution_id)
              asset_execution = resolve_execution(state.db, asset_execution_id)
              asset_ = resolve_asset(state.db, asset_id, false)

              notify_listeners(
                state,
                {:run, step.run_id},
                {:asset_dependency, from_execution_id, asset_execution_id, asset_execution,
                 asset_id, asset_}
              )
            else
              state
            end
          else
            state
          end

        {:reply, {:ok, type, path, blob_key}, state}

      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:subscribe_environments, pid}, _from, state) do
    case Sessions.get_environments(state.db) do
      {:ok, environments} ->
        environments_by_id =
          Enum.reduce(environments, %{}, fn {id, name, base_id}, acc ->
            Map.put(acc, id, %{name: name, base_id: base_id})
          end)

        environments_by_name =
          environments_by_id
          |> Map.values()
          |> Enum.reduce(%{}, fn environment, acc ->
            base_name =
              if environment.base_id do
                Map.fetch!(environments_by_id, environment.base_id).name
              end

            Map.put(acc, environment.name, %{base: base_name})
          end)

        {:ok, ref, state} = add_listener(state, :project, pid)
        {:reply, {:ok, environments_by_name, ref}, state}
    end
  end

  def handle_call({:subscribe_repositories, environment_name, pid}, _from, state) do
    {:ok, {environment_id}} = Sessions.get_environment_by_name(state.db, environment_name)
    {:ok, targets} = Sessions.get_latest_targets(state.db, environment_id)

    executing =
      state.sessions
      |> Map.values()
      |> Enum.reduce(MapSet.new(), fn session, executing ->
        executing |> MapSet.union(session.executing) |> MapSet.union(session.starting)
      end)

    {:ok, executions} = Runs.get_unassigned_executions(state.db)
    # TODO: get/include assigned (pending) executions

    executions =
      Enum.reduce(executions, %{}, fn execution, executions ->
        executions
        |> Map.put_new(execution.repository, {MapSet.new(), %{}})
        |> Map.update!(execution.repository, fn {repo_executing, repo_scheduled} ->
          if Enum.member?(executing, execution.execution_id) do
            {MapSet.put(repo_executing, execution.execution_id), repo_scheduled}
          else
            {repo_executing,
             Map.put(
               repo_scheduled,
               execution.execution_id,
               execution.execute_after || execution.created_at
             )}
          end
        end)
      end)

    {:ok, ref, state} =
      add_listener(state, {{:repositories, environment_id}, environment_id}, pid)

    {:reply, {:ok, targets, executions, ref}, state}
  end

  def handle_call({:subscribe_repository, repository, environment_name, pid}, _from, state) do
    {:ok, {environment_id}} = Sessions.get_environment_by_name(state.db, environment_name)
    {:ok, executions} = Runs.get_repository_executions(state.db, repository)
    {:ok, ref, state} = add_listener(state, {:repository, repository, environment_id}, pid)
    {:reply, {:ok, executions, ref}, state}
  end

  def handle_call({:subscribe_agents, environment_name, pid}, _from, state) do
    {:ok, {environment_id}} = Sessions.get_environment_by_name(state.db, environment_name)

    agents =
      state.agents
      |> Enum.map(fn {_, {_, session_id}} ->
        {session_id, Map.fetch!(state.sessions, session_id)}
      end)
      |> Enum.filter(fn {_, session} ->
        session.environment_id == environment_id
      end)
      |> Map.new(fn {session_id, session} ->
        {session_id, session.targets}
      end)

    {:ok, ref, state} = add_listener(state, {:agents, environment_id}, pid)
    {:reply, {:ok, agents, ref}, state}
  end

  def handle_call(
        {:subscribe_target, repository, target_name, environment_name, pid},
        _from,
        state
      ) do
    {:ok, {environment_id}} = Sessions.get_environment_by_name(state.db, environment_name)
    {:ok, target} = Sessions.get_target(state.db, repository, target_name, environment_id)
    {:ok, runs} = Runs.get_target_runs(state.db, repository, target_name)

    {:ok, ref, state} =
      add_listener(state, {:target, repository, target_name, environment_id}, pid)

    {:reply, {:ok, target, runs, ref}, state}
  end

  def handle_call({:subscribe_run, external_run_id, pid}, _from, state) do
    case Runs.get_run_by_external_id(state.db, external_run_id) do
      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}

      {:ok, run} ->
        parent =
          if run.parent_id do
            resolve_execution(state.db, run.parent_id)
          end

        {:ok, steps} = Runs.get_run_steps(state.db, run.id)

        steps =
          Map.new(steps, fn {step_id, step_external_id, parent_id, repository, target, memo_key,
                             created_at} ->
            {:ok, executions} = Runs.get_step_executions(state.db, step_id)
            {:ok, arguments} = Runs.get_step_arguments(state.db, step_id, true)

            arguments = Enum.map(arguments, &build_value(&1, state))

            environment_names =
              executions
              |> Enum.map(&elem(&1, 2))
              |> Enum.uniq()
              |> Map.new(fn environment_id ->
                case Sessions.get_environment_by_id(state.db, environment_id) do
                  {:ok, {environment_name}} ->
                    {environment_id, environment_name}
                end
              end)

            {step_external_id,
             %{
               repository: repository,
               target: target,
               parent_id: parent_id,
               memo_key: memo_key,
               created_at: created_at,
               arguments: arguments,
               executions:
                 Map.new(executions, fn {execution_id, attempt, environment_id, execute_after,
                                         created_at, _session_id, assigned_at} ->
                   {:ok, asset_ids} = Results.get_assets_for_execution(state.db, execution_id)
                   assets = Map.new(asset_ids, &{&1, resolve_asset(state.db, &1, false)})

                   {:ok, result_dependencies} =
                     Runs.get_result_dependencies(state.db, execution_id)

                   # TODO: batch? get `get_result_dependencies` to resolve?
                   result_dependencies =
                     Map.new(result_dependencies, fn {dependency_id} ->
                       {dependency_id, resolve_execution(state.db, dependency_id)}
                     end)

                   {:ok, asset_dependencies} = Runs.get_asset_dependencies(state.db, execution_id)

                   asset_dependencies =
                     Map.new(asset_dependencies, fn {asset_id} ->
                       {asset_id, resolve_asset(state.db, asset_id, true)}
                     end)

                   {result, completed_at} =
                     case Results.get_result(state.db, execution_id, true) do
                       {:ok, {result, completed_at}} ->
                         {result, completed_at}

                       {:ok, nil} ->
                         {nil, nil}
                     end

                   result = build_result(result, state)

                   {:ok, children} =
                     Runs.get_execution_children(state.db, execution_id)

                   {attempt,
                    %{
                      execution_id: execution_id,
                      environment_name: Map.fetch!(environment_names, environment_id),
                      created_at: created_at,
                      execute_after: execute_after,
                      assigned_at: assigned_at,
                      completed_at: completed_at,
                      assets: assets,
                      result_dependencies: result_dependencies,
                      asset_dependencies: asset_dependencies,
                      result: result,
                      children: children
                    }}
                 end)
             }}
          end)

        {:ok, ref, state} = add_listener(state, {:run, run.id}, pid)
        {:reply, {:ok, run, parent, steps, ref}, state}
    end
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
        |> Map.update!(:waiting, fn waiting ->
          waiting
          |> Enum.map(fn {execution_id, execution_waiting} ->
            {execution_id,
             Enum.reject(execution_waiting, fn {s_id, _} ->
               s_id == session_id
             end)}
          end)
          |> Enum.reject(fn {_execution_id, execution_waiting} ->
            Enum.empty?(execution_waiting)
          end)
          |> Map.new()
        end)

      state = flush_notifications(state)

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

    {:ok, executions} = Runs.get_unassigned_executions(state.db)
    now = System.os_time(:millisecond)

    {executions_due, executions_future, executions_defer} =
      split_executions(executions, now)

    state =
      executions_defer
      |> Enum.reverse()
      |> Enum.reduce(state, fn {execution_id, defer_id, run_id, repository}, state ->
        case record_and_notify_result(
               state,
               execution_id,
               {:deferred, defer_id},
               run_id,
               repository
             ) do
          {:ok, state} -> state
          {:error, :already_recorded} -> state
        end
      end)

    {state, assigned, _unassigned} =
      executions_due
      |> Enum.reverse()
      |> Enum.reduce(
        {state, [], []},
        fn
          execution, {state, assigned, unassigned} ->
            # TODO: choose session before resolving arguments?
            {:ok, arguments} =
              case Results.get_latest_checkpoint(state.db, execution.step_id) do
                {:ok, nil} ->
                  Runs.get_step_arguments(state.db, execution.step_id)

                {:ok, {checkpoint_id, _, _, _}} ->
                  Results.get_checkpoint_arguments(state.db, checkpoint_id)
              end

            if is_execution_ready?(state, execution.wait_for, arguments) do
              case choose_session(state, execution) do
                {:ok, session_id} ->
                  {:ok, assigned_at} =
                    Runs.assign_execution(state.db, execution.execution_id, session_id)

                  state =
                    state
                    |> update_in(
                      [Access.key(:sessions), session_id, :starting],
                      &MapSet.put(&1, execution.execution_id)
                    )
                    |> send_session(
                      session_id,
                      {:execute, execution.execution_id, execution.repository, execution.target,
                       arguments, execution.run_external_id}
                    )

                  {state, [{execution, assigned_at} | assigned], unassigned}

                {:error, :no_session} ->
                  {state, assigned, [execution | unassigned]}
              end
            else
              {state, assigned, [execution | unassigned]}
            end
        end
      )

    state =
      assigned
      |> Enum.group_by(fn {execution, _assigned_at} -> execution.run_id end)
      |> Enum.reduce(state, fn {run_id, executions}, state ->
        assigned =
          Map.new(executions, fn {execution, assigned_at} ->
            {execution.execution_id, assigned_at}
          end)

        notify_listeners(state, {:run, run_id}, {:assigned, assigned})
      end)

    assigned_groups =
      assigned
      |> Enum.group_by(fn {execution, _} -> execution.environment_id end)
      |> Map.new(fn {environment_id, executions} ->
        {environment_id,
         executions
         |> Enum.group_by(
           fn {execution, _} -> execution.repository end,
           fn {execution, _} -> execution.execution_id end
         )
         |> Map.new(fn {k, v} -> {k, MapSet.new(v)} end)}
      end)

    state =
      Enum.reduce(assigned_groups, state, fn {environment_id, environment_executions}, state ->
        notify_listeners(
          state,
          {:repositories, environment_id},
          {:assigned, environment_executions}
        )
      end)

    state =
      Enum.reduce(assigned_groups, state, fn {environment_id, environment_executions}, state ->
        Enum.reduce(environment_executions, state, fn {repository, execution_ids}, state ->
          repository_executions =
            Enum.reduce(assigned, %{}, fn {execution, assigned_at}, repository_executions ->
              if MapSet.member?(execution_ids, execution.execution_id) do
                Map.put(repository_executions, execution.execution_id, assigned_at)
              else
                repository_executions
              end
            end)

          notify_listeners(
            state,
            {:repository, repository, environment_id},
            {:assigned, repository_executions}
          )
        end)
      end)

    next_execute_after =
      executions_future
      |> Enum.map(& &1.execute_after)
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

    state = flush_notifications(state)

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
          state
          |> update_in(
            [Access.key(:sessions), session_id],
            &Map.merge(&1, %{agent: nil, expire_timer: expire_timer})
          )
          |> notify_agent(session_id)
          |> flush_notifications()

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
      concurrency: 0,
      environment_id: nil
    }
  end

  defp split_executions(executions, now) do
    {executions_due, executions_future, executions_defer, _} =
      executions
      |> Enum.reverse()
      |> Enum.reduce(
        {[], [], [], %{}},
        fn execution, {due, future, defer, defer_keys} ->
          defer_key =
            execution.defer_key &&
              {execution.repository, execution.target, execution.environment_id,
               execution.defer_key}

          defer_id = defer_key && Map.get(defer_keys, defer_key)

          if defer_id do
            {due, future,
             [{execution.execution_id, defer_id, execution.run_id, execution.repository} | defer],
             defer_keys}
          else
            defer_keys =
              if defer_key do
                Map.put(defer_keys, defer_key, execution.execution_id)
              else
                defer_keys
              end

            if is_nil(execution.execute_after) || execution.execute_after <= now do
              {[execution | due], future, defer, defer_keys}
            else
              {due, [execution | future], defer, defer_keys}
            end
          end
        end
      )

    {executions_due, executions_future, executions_defer}
  end

  defp rerun_step(state, step, environment_id, execute_after) do
    # TODO: only get run if needed for notify?
    {:ok, run} = Runs.get_run_by_id(state.db, step.run_id)

    case Runs.rerun_step(state.db, step.id, environment_id, execute_after) do
      {:ok, execution_id, attempt, created_at} ->
        {:ok, {environment_name}} = Sessions.get_environment_by_id(state.db, environment_id)

        state =
          notify_listeners(
            state,
            {:run, step.run_id},
            {:execution, step.external_id, attempt, execution_id, environment_name, created_at,
             execute_after}
          )

        execute_at = execute_after || created_at

        state =
          state
          |> notify_listeners(
            {:repositories, environment_id},
            {:scheduled, step.repository, execution_id, execute_at}
          )
          |> notify_listeners(
            {:repository, step.repository, environment_id},
            {:scheduled, execution_id, step.target, run.external_id, step.external_id, attempt,
             execute_after, created_at}
          )

        send(self(), :execute)
        {:ok, execution_id, attempt, state}
    end
  end

  defp result_retryable?(result) do
    case result do
      {:error, _, _, _, _} -> true
      :abandoned -> true
      _ -> false
    end
  end

  defp resolve_execution(db, execution_id) do
    {:ok, {external_run_id, external_step_id, step_attempt, repository, target}} =
      Runs.get_run_by_execution(db, execution_id)

    %{
      run_id: external_run_id,
      step_id: external_step_id,
      attempt: step_attempt,
      repository: repository,
      target: target
    }
  end

  defp resolve_asset(db, asset_id, include_execution) do
    {:ok, {execution_id, type, path, blob_key, created_at, metadata}} =
      Results.get_asset_by_id(db, asset_id, true)

    result = %{
      type: type,
      path: path,
      metadata: metadata,
      blob_key: blob_key,
      execution_id: execution_id,
      created_at: created_at
    }

    if include_execution do
      Map.put(result, :execution, resolve_execution(db, execution_id))
    else
      result
    end
  end

  defp resolve_placeholders(placeholders, db) do
    Map.new(placeholders, fn {key, value} ->
      value =
        case value do
          {execution_id, nil} ->
            {:execution, execution_id, resolve_execution(db, execution_id)}

          {nil, asset_id} ->
            {:asset, asset_id, resolve_asset(db, asset_id, true)}
        end

      {key, value}
    end)
  end

  defp build_value(value, state) do
    case value do
      {{:raw, content}, format, placeholders} ->
        {{:raw, content}, format, resolve_placeholders(placeholders, state.db)}

      {{:blob, key, metadata}, format, placeholders} ->
        {{:blob, key, metadata}, format, resolve_placeholders(placeholders, state.db)}
    end
  end

  defp build_result(result, state) do
    case result do
      {:value, value} ->
        {:value, build_value(value, state)}

      {:deferred, execution_id} ->
        {:deferred, execution_id, resolve_execution(state.db, execution_id)}

      {:cached, execution_id} ->
        {:cached, execution_id, resolve_execution(state.db, execution_id)}

      other ->
        other
    end
  end

  defp record_and_notify_result(state, execution_id, result, run_id, repository) do
    {:ok, environment_id} = Runs.get_environment_for_execution(state.db, execution_id)

    case Results.record_result(state.db, execution_id, result) do
      {:ok, created_at} ->
        state = notify_waiting(state, execution_id)
        result = build_result(result, state)

        state =
          state
          |> notify_listeners(
            {:run, run_id},
            {:result, execution_id, result, created_at}
          )
          |> notify_listeners(
            {:repositories, environment_id},
            {:completed, repository, execution_id}
          )
          |> notify_listeners(
            {:repository, repository, environment_id},
            {:completed, execution_id}
          )

        # TODO: only if there's an execution waiting for this result?
        send(self(), :execute)

        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_result(state, execution_id, result) do
    case Results.has_result?(state.db, execution_id) do
      {:ok, true} ->
        {:ok, state}

      {:ok, false} ->
        {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)
        {:ok, environment_id} = Runs.get_environment_for_execution(state.db, execution_id)

        {retry_id, state} =
          if result_retryable?(result) && step.retry_count > 0 do
            {:ok, executions} = Runs.get_step_executions(state.db, step.id)

            attempts = Enum.count(executions)

            if attempts <= step.retry_count do
              # TODO: add jitter (within min/max delay)
              delay_s =
                step.retry_delay_min +
                  (attempts - 1) / (step.retry_count - 1) *
                    (step.retry_delay_max - step.retry_delay_min)

              execute_after = System.os_time(:millisecond) + delay_s * 1000
              # TODO: do cache lookup?
              {:ok, retry_id, _, state} = rerun_step(state, step, environment_id, execute_after)
              {retry_id, state}
            else
              {nil, state}
            end
          else
            {:ok, run} = Runs.get_run_by_id(state.db, step.run_id)

            if run.recurrent do
              {:ok, executions} = Runs.get_step_executions(state.db, step.id)

              if Enum.all?(executions, &elem(&1, 5)) do
                now = System.os_time(:millisecond)

                last_assigned_at =
                  executions |> Enum.map(&elem(&1, 5)) |> Enum.max(&>=/2, fn -> nil end)

                execute_after =
                  if last_assigned_at && now - last_assigned_at < @recurrent_rate_limit_ms do
                    last_assigned_at + @recurrent_rate_limit_ms
                  end

                {:ok, _, _, state} = rerun_step(state, step, environment_id, execute_after)

                {nil, state}
              else
                {nil, state}
              end
            else
              {nil, state}
            end
          end

        result =
          case result do
            {:error, type, message, frames} -> {:error, type, message, frames, retry_id}
            :abandoned -> {:abandoned, retry_id}
            other -> other
          end

        state =
          case record_and_notify_result(
                 state,
                 execution_id,
                 result,
                 step.run_id,
                 step.repository
               ) do
            {:ok, state} -> state
          end

        {:ok, state}
    end
  end

  defp resolve_result(execution_id, db) do
    # TODO: check execution exists?
    case Results.get_result(db, execution_id) do
      {:ok, nil} ->
        {:pending, execution_id}

      {:ok, {result, _}} ->
        case result do
          {:reference, execution_id} ->
            resolve_result(execution_id, db)

          {:error, _, _, _, execution_id} when not is_nil(execution_id) ->
            resolve_result(execution_id, db)

          {:abandoned, execution_id} when not is_nil(execution_id) ->
            resolve_result(execution_id, db)

          {:deferred, execution_id} when not is_nil(execution_id) ->
            resolve_result(execution_id, db)

          {:cached, execution_id} when not is_nil(execution_id) ->
            resolve_result(execution_id, db)

          other ->
            {:ok, other}
        end
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
    if Map.has_key?(state.topics, topic) do
      update_in(state.notifications[topic], &[payload | &1 || []])
    else
      state
    end
  end

  defp flush_notifications(state) do
    Enum.each(state.notifications, fn {topic, notifications} ->
      notifications = Enum.reverse(notifications)

      state.topics
      |> Map.get(topic, %{})
      |> Enum.each(fn {ref, pid} ->
        send(pid, {:topic, ref, notifications})
      end)
    end)

    Map.put(state, :notifications, %{})
  end

  defp notify_agent(state, session_id) do
    session = Map.fetch!(state.sessions, session_id)
    targets = if session.agent, do: session.targets
    notify_listeners(state, {:agents, session.environment_id}, {:agent, session_id, targets})
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

  defp start_run(state, repository, target_name, arguments, environment_id, opts, parent \\ nil) do
    case Runs.start_run(state.db, repository, target_name, arguments, environment_id, opts) do
      {:ok, _run_id, external_run_id, _step_id, external_step_id, execution_id, attempt, result,
       created_at, child_added} ->
        state =
          if child_added do
            {parent_run_id, parent_id} = parent

            child =
              {external_run_id, external_step_id, execution_id, repository, target_name,
               created_at}

            notify_listeners(state, {:run, parent_run_id}, {:child, parent_id, child})
          else
            state
          end

        state =
          notify_listeners(
            state,
            {:target, repository, target_name, environment_id},
            {:run, external_run_id, created_at}
          )

        state =
          if !result do
            # TODO: neater way to get execute_after?
            execute_after = Keyword.get(opts, :execute_after)
            execute_at = execute_after || created_at

            state =
              state
              |> notify_listeners(
                {:repositories, environment_id},
                {:scheduled, repository, execution_id, execute_at}
              )
              |> notify_listeners(
                {:repository, repository, environment_id},
                {:scheduled, execution_id, target_name, external_run_id, external_step_id,
                 attempt, execute_after, created_at}
              )

            send(self(), :execute)

            state
          else
            state
          end

        {{:ok, external_run_id, external_step_id, execution_id}, state}
    end
  end

  defp schedule_step(
         state,
         run_id,
         parent_id,
         repository,
         target_name,
         arguments,
         environment_id,
         opts
       ) do
    {:ok, run} = Runs.get_run_by_id(state.db, run_id)

    case Runs.schedule_step(
           state.db,
           run_id,
           parent_id,
           repository,
           target_name,
           arguments,
           environment_id,
           opts
         ) do
      {:ok, _step_id, external_step_id, execution_id, attempt, created_at, memoised, result,
       child_added} ->
        state =
          if !memoised do
            memo_key = Keyword.get(opts, :memo_key)
            arguments = Enum.map(arguments, &build_value(&1, state))

            notify_listeners(
              state,
              {:run, run_id},
              {:step, external_step_id, repository, target_name, memo_key, parent_id, created_at,
               arguments}
            )
          else
            state
          end

        state =
          if child_added do
            child =
              {run.external_id, external_step_id, execution_id, repository, target_name,
               created_at}

            notify_listeners(state, {:run, run_id}, {:child, parent_id, child})
          else
            state
          end

        execute_after = Keyword.get(opts, :execute_after)

        state =
          if !memoised do
            {:ok, {environment_name}} = Sessions.get_environment_by_id(state.db, environment_id)

            notify_listeners(
              state,
              {:run, run_id},
              {:execution, external_step_id, attempt, execution_id, environment_name, created_at,
               execute_after}
            )
          else
            state
          end

        state =
          if result do
            result = build_result(result, state)

            notify_listeners(
              state,
              {:run, run_id},
              {:result, execution_id, result, created_at}
            )
          else
            state
          end

        state =
          if !memoised && !result do
            execute_at = execute_after || created_at

            state =
              state
              |> notify_listeners(
                {:repositories, environment_id},
                {:scheduled, repository, execution_id, execute_at}
              )
              |> notify_listeners(
                {:repository, repository, environment_id},
                {:scheduled, execution_id, target_name, run.external_id, external_step_id,
                 attempt, execute_after, created_at}
              )

            send(self(), :execute)

            state
          else
            state
          end

        {{:ok, run.external_id, external_step_id, execution_id}, state}
    end
  end

  defp session_at_capacity?(session) do
    if session.concurrency != 0 do
      load = MapSet.size(session.starting) + MapSet.size(session.executing)
      load >= session.concurrency
    else
      false
    end
  end

  defp is_execution_ready?(state, wait_for, arguments) do
    Enum.all?(wait_for || [], fn index ->
      case Enum.at(arguments, index) do
        {_, _, placeholders} ->
          placeholders
          |> Map.values()
          |> Enum.map(fn {execution_id, _} -> execution_id end)
          |> Enum.reject(&is_nil/1)
          |> Enum.all?(fn execution_id ->
            case resolve_result(execution_id, state.db) do
              {:ok, _} -> true
              {:pending, _} -> false
            end
          end)

        nil ->
          true
      end
    end)
  end

  defp choose_session(state, execution) do
    session_ids =
      state.targets
      |> Map.get(execution.repository, %{})
      |> Map.get(execution.target, MapSet.new())
      |> Enum.filter(fn session_id ->
        session = state.sessions[session_id]

        session.environment_id == execution.environment_id && session.agent &&
          not session_at_capacity?(session)
      end)

    if Enum.any?(session_ids) do
      {:ok, Enum.random(session_ids)}
    else
      {:error, :no_session}
    end
  end

  defp notify_waiting(state, execution_id) do
    {execution_waiting, waiting} = Map.pop(state.waiting, execution_id)

    if execution_waiting do
      case resolve_result(execution_id, state.db) do
        {:pending, execution_id} ->
          waiting =
            Map.update(waiting, execution_id, execution_waiting, &(&1 ++ execution_waiting))

          Map.put(state, :waiting, waiting)

        {:ok, result} ->
          state = Map.put(state, :waiting, waiting)

          Enum.reduce(execution_waiting, state, fn {session_id, request_id}, state ->
            send_session(state, session_id, {:result, request_id, result})
          end)
      end
    else
      state
    end
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

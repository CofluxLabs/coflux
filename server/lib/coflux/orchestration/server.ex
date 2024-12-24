defmodule Coflux.Orchestration.Server do
  use GenServer, restart: :transient

  alias Coflux.Store
  alias Coflux.MapUtils

  alias Coflux.Orchestration.{
    Environments,
    Sessions,
    Runs,
    Results,
    TagSets,
    Launches,
    Manifests,
    Observations
  }

  @session_timeout_ms 5_000
  @sensor_rate_limit_ms 5_000

  defmodule State do
    defstruct project_id: nil,
              db: nil,
              execute_timer: nil,

              # id -> %{name, base_id, status, pools}
              environments: %{},

              # name -> id
              environment_names: %{},

              # ref -> {pid, session_id}
              agents: %{},

              # session_id -> %{external_id, agent, targets, queue, starting, executing, expire_timer, concurrency, environment_id}
              sessions: %{},

              # external_id -> session_id
              session_ids: %{},

              # {repository, target} -> %{type, session_ids}
              targets: %{},

              # ref -> topic
              listeners: %{},

              # topic -> %{ref -> pid}
              topics: %{},

              # topic -> [notification]
              notifications: %{},

              # execution_id -> [{session_id, request_id}]
              waiting: %{},

              # task_ref -> launch_id
              launch_tasks: %{}
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

        {:ok, state, {:continue, :setup}}
    end
  end

  def handle_continue(:setup, state) do
    {:ok, environments} = Environments.get_all_environments(state.db)

    environment_names =
      Map.new(environments, fn {environment_id, environment} ->
        {environment.name, environment_id}
      end)

    state =
      state
      |> Map.put(:environments, environments)
      |> Map.put(:environment_names, environment_names)

    {:ok, pending} = Runs.get_pending_assignments(state.db)

    state =
      Enum.reduce(pending, state, fn {execution_id}, state ->
        {:ok, state} = process_result(state, execution_id, :abandoned)
        state
      end)

    {:noreply, state}
  end

  def handle_call(:get_environments, _from, state) do
    environments =
      state.environments
      |> Enum.filter(fn {_, e} -> e.status != :archived end)
      |> Map.new(fn {environment_id, environment} ->
        {environment_id, %{name: environment.name, base_id: environment.base_id}}
      end)

    {:reply, {:ok, environments}, state}
  end

  def handle_call({:create_environment, name, base_id, pools}, _from, state) do
    case Environments.create_environment(state.db, name, base_id, pools) do
      {:ok, environment_id, environment} ->
        state =
          state
          |> put_in([Access.key(:environments), environment_id], environment)
          |> put_in([Access.key(:environment_names), environment.name], environment_id)
          |> notify_listeners(:environments, {:environment, environment_id, environment})
          |> flush_notifications()

        {:reply, {:ok, environment_id}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:update_environment, environment_id, updates}, _from, state) do
    case Environments.update_environment(state.db, environment_id, updates) do
      {:ok, environment} ->
        original_name = state.environments[environment_id].name

        state =
          state
          |> put_in([Access.key(:environments), environment_id], environment)
          |> Map.update!(:environment_names, fn environment_names ->
            environment_names
            |> Map.delete(original_name)
            |> Map.put(environment.name, environment_id)
          end)
          |> notify_listeners(:environments, {:environment, environment_id, environment})
          |> flush_notifications()

        send(self(), :execute)

        # TODO: return updated?
        {:reply, :ok, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:pause_environment, environment_id}, _from, state) do
    case Environments.pause_environment(state.db, environment_id) do
      :ok ->
        state =
          state
          |> put_in([Access.key(:environments), environment_id, Access.key(:status)], :paused)
          |> notify_listeners(:environments, {:status, environment_id, :paused})
          |> flush_notifications()

        {:reply, :ok, state}
    end
  end

  def handle_call({:resume_environment, environment_id}, _from, state) do
    case Environments.resume_environment(state.db, environment_id) do
      :ok ->
        state =
          state
          |> put_in([Access.key(:environments), environment_id, Access.key(:status)], :active)
          |> notify_listeners(:environments, {:status, environment_id, :active})
          |> flush_notifications()

        send(self(), :execute)

        {:reply, :ok, state}
    end
  end

  def handle_call({:archive_environment, environment_id}, _from, state) do
    case Environments.archive_environment(state.db, environment_id) do
      :ok ->
        state =
          state.sessions
          |> Enum.filter(fn {_, s} -> s.environment_id == environment_id end)
          |> Enum.reduce(state, fn {session_id, session}, state ->
            state =
              if session.agent do
                {pid, ^session_id} = Map.fetch!(state.agents, session.agent)
                send(pid, :stop)
                Map.update!(state, :agents, &Map.delete(&1, session.agent))
              else
                state
              end

            remove_session(state, session_id)
          end)

        state =
          case Runs.get_pending_executions_for_environment(state.db, environment_id) do
            {:ok, executions} ->
              Enum.reduce(executions, state, fn {execution_id, _run_id, repository}, state ->
                case record_and_notify_result(
                       state,
                       execution_id,
                       :cancelled,
                       repository
                     ) do
                  {:ok, state} -> state
                  {:error, :already_recorded} -> state
                end
              end)
          end

        state =
          state
          |> put_in([Access.key(:environments), environment_id, Access.key(:status)], :archived)
          |> notify_listeners(:environments, {:status, environment_id, :archived})
          |> flush_notifications()

        {:reply, :ok, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:register_manifests, environment_name, manifests},
        _from,
        state
      ) do
    case lookup_environment_by_name(state, environment_name) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, environment_id, _} ->
        case Manifests.register_manifests(state.db, environment_id, manifests) do
          :ok ->
            state =
              manifests
              |> Enum.reduce(state, fn {repository, manifest}, state ->
                state =
                  Enum.reduce(manifest.workflows, state, fn {target_name, target}, state ->
                    notify_listeners(
                      state,
                      {:workflow, repository, target_name, environment_id},
                      {:target, target}
                    )
                  end)

                state =
                  Enum.reduce(manifest.sensors, state, fn {target_name, target}, state ->
                    notify_listeners(
                      state,
                      {:sensor, repository, target_name, environment_id},
                      {:target, target}
                    )
                  end)

                state
              end)
              |> notify_listeners(
                {:repositories, environment_id},
                {:manifests, manifests}
              )
              |> notify_listeners(
                {:targets, environment_id},
                {:manifests,
                 Map.new(manifests, fn {repository_name, targets} ->
                   {repository_name,
                    %{
                      workflows: MapSet.new(Map.keys(targets.workflows)),
                      sensors: MapSet.new(Map.keys(targets.sensors))
                    }}
                 end)}
              )
              |> flush_notifications()

            {:reply, :ok, state}
        end
    end
  end

  def handle_call({:archive_repository, environment_name, repository_name}, _from, state) do
    case lookup_environment_by_name(state, environment_name) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, environment_id, _} ->
        case Manifests.archive_repository(state.db, environment_id, repository_name) do
          :ok ->
            state =
              state
              |> notify_listeners(
                {:repositories, environment_id},
                {:manifest, repository_name, nil}
              )
              |> flush_notifications()

            {:reply, :ok, state}
        end
    end
  end

  def handle_call({:get_workflow, environment_name, repository, target_name}, _from, state) do
    with {:ok, environment_id, _} <- lookup_environment_by_name(state, environment_name),
         {:ok, workflow} <-
           Manifests.get_latest_workflow(state.db, environment_id, repository, target_name) do
      {:reply, {:ok, workflow}, state}
    else
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:start_session, environment_name, launch_id, provides, concurrency, pid},
        _from,
        state
      ) do
    case lookup_environment_by_name(state, environment_name) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, environment_id, _} ->
        case lookup_launch(state, launch_id, environment_id) do
          {:error, error} ->
            {:reply, {:error, error}, state}

          {:ok, launch_id, pool_id} ->
            provides =
              if launch_id,
                do: state.environments[environment_id].pools[pool_id].provides,
                else: provides

            case Sessions.start_session(state.db, environment_id, provides, launch_id) do
              {:ok, session_id, external_session_id} ->
                ref = Process.monitor(pid)

                session = %{
                  external_id: external_session_id,
                  agent: ref,
                  targets: %{},
                  queue: [],
                  starting: MapSet.new(),
                  executing: MapSet.new(),
                  expire_timer: nil,
                  concurrency: concurrency,
                  environment_id: environment_id,
                  provides: provides
                }

                state =
                  state
                  |> put_in([Access.key(:sessions), session_id], session)
                  |> put_in([Access.key(:session_ids), external_session_id], session_id)
                  |> put_in([Access.key(:agents), ref], {pid, session_id})
                  |> notify_agent(session_id)
                  |> flush_notifications()

                {:reply, {:ok, external_session_id}, state}
            end
        end
    end
  end

  def handle_call({:resume_session, external_session_id, pid}, _from, state) do
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
            &Map.merge(&1, %{agent: ref, queue: []})
          )
          |> notify_agent(session_id)

        executions = MapSet.union(session.executing, session.starting)

        send(self(), :execute)

        state = flush_notifications(state)
        {:reply, {:ok, external_session_id, executions}, state}

      :error ->
        {:reply, {:error, :no_session}, state}
    end
  end

  def handle_call({:declare_targets, external_session_id, targets}, _from, state) do
    session_id = Map.fetch!(state.session_ids, external_session_id)

    state =
      state
      |> assign_targets(targets, session_id)
      |> notify_agent(session_id)
      |> flush_notifications()

    send(self(), :execute)
    {:reply, :ok, state}
  end

  def handle_call({:start_run, repository, target_name, type, arguments, opts}, _from, state) do
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
          Runs.get_environment_id_for_execution(state.db, parent_id)

        nil ->
          environment_name = Keyword.get(opts, :environment)

          case lookup_environment_by_name(state, environment_name) do
            {:ok, environment_id, _} -> {:ok, environment_id}
            {:error, :environment_invalid} -> {:ok, nil}
          end
      end

    if environment_id do
      {:ok, external_run_id, external_step_id, execution_id, state} =
        schedule_run(state, repository, target_name, type, arguments, environment_id, opts)

      send(self(), :execute)
      state = flush_notifications(state)

      {:reply, {:ok, external_run_id, external_step_id, execution_id}, state}
    else
      {:reply, {:error, :environment_invalid}, state}
    end
  end

  def handle_call(
        {:schedule_step, parent_id, repository, target_name, type, arguments, opts},
        _from,
        state
      ) do
    {:ok, parent_step} = Runs.get_step_for_execution(state.db, parent_id)
    {:ok, environment_id} = Runs.get_environment_id_for_execution(state.db, parent_id)
    {:ok, run} = Runs.get_run_by_id(state.db, parent_step.run_id)

    cache_environment_ids = get_cache_environment_ids(state, environment_id)

    case Runs.schedule_step(
           state.db,
           run.id,
           parent_id,
           repository,
           target_name,
           type,
           arguments,
           environment_id,
           cache_environment_ids,
           opts
         ) do
      {:ok, external_step_id, execution_id, attempt, created_at, memo_hit, child_added} ->
        execute_after = Keyword.get(opts, :execute_after)
        requires = Keyword.get(opts, :requires) || %{}

        state =
          if !memo_hit do
            is_memoised = !!Keyword.get(opts, :memo)
            arguments = Enum.map(arguments, &build_value(&1, state.db))

            notify_listeners(
              state,
              {:run, run.id},
              {:step, external_step_id, repository, target_name, type, is_memoised, parent_id,
               created_at, arguments, requires, attempt, execution_id, environment_id,
               execute_after}
            )
          else
            state
          end

        state =
          if child_added do
            notify_listeners(
              state,
              {:run, run.id},
              {:child, parent_id,
               {run.external_id, external_step_id, repository, target_name, type}}
            )
          else
            state
          end

        state =
          if !memo_hit do
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

        state =
          state
          |> notify_listeners(
            {:targets, environment_id},
            {:step, repository, target_name, type, run.external_id, external_step_id, attempt}
          )
          |> flush_notifications()

        {:reply, {:ok, run.external_id, external_step_id, execution_id}, state}
    end
  end

  def handle_call({:rerun_step, external_step_id, environment_name}, _from, state) do
    # TODO: abort/cancel any running/scheduled retry? (for the same environment) (and reference this retry?)
    case lookup_environment_by_name(state, environment_name) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, environment_id, _} ->
        {:ok, step} = Runs.get_step_by_external_id(state.db, external_step_id)

        base_execution_id =
          if step.parent_id do
            step.parent_id
          else
            case Runs.get_first_step_execution_id(state.db, step.id) do
              {:ok, execution_id} -> execution_id
            end
          end

        {:ok, base_environment_id} =
          Runs.get_environment_id_for_execution(state.db, base_execution_id)

        if base_environment_id == environment_id ||
             is_environment_ancestor?(state, base_environment_id, environment_id) do
          {:ok, execution_id, attempt, state} = rerun_step(state, step, environment_id)
          state = flush_notifications(state)
          {:reply, {:ok, execution_id, attempt}, state}
        else
          {:reply, {:error, :environment_invalid}, state}
        end
    end
  end

  def handle_call({:cancel_execution, execution_id}, _from, state) do
    execution_id =
      case Results.get_result(state.db, execution_id) do
        {:ok, {{:spawned, spawned_execution_id}, _created_at}} -> spawned_execution_id
        {:ok, _other} -> execution_id
      end

    {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)
    {:ok, executions} = Runs.get_run_executions(state.db, step.run_id)

    executions = filter_execution_children(execution_id, executions)

    state =
      Enum.reduce(
        executions,
        state,
        fn {execution_id, _parent_id, repository, assigned_at, completed_at}, state ->
          if !completed_at do
            state =
              case record_and_notify_result(
                     state,
                     execution_id,
                     :cancelled,
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
        end
      )

    state = flush_notifications(state)

    {:reply, :ok, state}
  end

  def handle_call({:record_heartbeats, executions, external_session_id}, _from, state) do
    # TODO: handle execution statuses?
    case Map.fetch(state.session_ids, external_session_id) do
      {:ok, session_id} ->
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
                {:ok, state} = process_result(state, execution_id, :abandoned)
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

      :error ->
        {:reply, {:error, :session_invalid}, state}
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
    case process_result(state, execution_id, result) do
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
      case resolve_result(state.db, execution_id) do
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

  def handle_call({:put_asset, execution_id, type, path, blob_key, size, metadata}, _from, state) do
    {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)

    {:ok, asset_id} =
      Results.get_or_create_asset(state.db, execution_id, type, path, blob_key, size, metadata)

    asset = resolve_asset(state.db, asset_id)
    state = notify_listeners(state, {:run, step.run_id}, {:asset, execution_id, asset_id, asset})
    {:reply, {:ok, asset_id}, state}
  end

  def handle_call({:get_asset, asset_id, opts}, _from, state) do
    load_metadata = opts[:load_metadata]

    case Results.get_asset_by_id(state.db, asset_id, load_metadata) do
      {:ok, {type, path, blob_key, _size, metadata}} ->
        {:reply, {:ok, type, path, blob_key, metadata}, state}

      {:ok, nil} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:record_logs, execution_id, messages}, _from, state) do
    {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)

    case Observations.record_logs(state.db, execution_id, messages) do
      :ok ->
        messages =
          Enum.map(messages, fn {timestamp, level, template, values} ->
            {execution_id, timestamp, level, template,
             Map.new(values, fn {k, v} -> {k, build_value(v, state.db)} end)}
          end)

        state =
          state
          |> notify_listeners({:logs, step.run_id}, {:messages, messages})
          |> notify_listeners({:run, step.run_id}, {:log_counts, execution_id, length(messages)})
          |> flush_notifications()

        {:reply, :ok, state}
    end
  end

  def handle_call({:subscribe_environments, pid}, _from, state) do
    {:ok, ref, state} = add_listener(state, :environments, pid)
    {:reply, {:ok, state.environments, ref}, state}
  end

  def handle_call({:subscribe_repositories, environment_id, pid}, _from, state) do
    case lookup_environment_by_id(state, environment_id) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, _} ->
        {:ok, manifests} = Manifests.get_latest_manifests(state.db, environment_id)

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
          add_listener(state, {:repositories, environment_id}, pid)

        {:reply, {:ok, manifests, executions, ref}, state}
    end
  end

  def handle_call({:subscribe_repository, repository, environment_id, pid}, _from, state) do
    case lookup_environment_by_id(state, environment_id) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, _} ->
        {:ok, executions} = Runs.get_repository_executions(state.db, repository)
        {:ok, ref, state} = add_listener(state, {:repository, repository, environment_id}, pid)
        {:reply, {:ok, executions, ref}, state}
    end
  end

  def handle_call({:subscribe_agents, environment_id, pid}, _from, state) do
    case lookup_environment_by_id(state, environment_id) do
      {:error, error} ->
        {:reply, {:error, error}, state}

      {:ok, _} ->
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
  end

  def handle_call(
        {:subscribe_workflow, repository, target_name, environment_id, pid},
        _from,
        state
      ) do
    with {:ok, _} <- lookup_environment_by_id(state, environment_id),
         {:ok, workflow} <-
           Manifests.get_latest_workflow(state.db, environment_id, repository, target_name),
         {:ok, instruction} <-
           if(workflow && workflow.instruction_id,
             do: Manifests.get_instruction(state.db, workflow.instruction_id),
             else: {:ok, nil}
           ),
         {:ok, runs} = Runs.get_target_runs(state.db, repository, target_name, environment_id) do
      {:ok, ref, state} =
        add_listener(state, {:workflow, repository, target_name, environment_id}, pid)

      {:reply, {:ok, workflow, instruction, runs, ref}, state}
    else
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(
        {:subscribe_sensor, repository, target_name, environment_id, pid},
        _from,
        state
      ) do
    with {:ok, _} <- lookup_environment_by_id(state, environment_id),
         {:ok, sensor} <-
           Manifests.get_latest_sensor(state.db, environment_id, repository, target_name),
         {:ok, instruction} <-
           if(sensor.instruction_id,
             do: Manifests.get_instruction(state.db, sensor.instruction_id),
             else: {:ok, nil}
           ),
         {:ok, runs} = Runs.get_target_runs(state.db, repository, target_name, environment_id) do
      {:ok, ref, state} =
        add_listener(state, {:sensor, repository, target_name, environment_id}, pid)

      {:reply, {:ok, sensor, instruction, runs, ref}, state}
    else
      {:error, error} ->
        {:reply, {:error, error}, state}
    end
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
        {:ok, log_counts} = Observations.get_counts_for_run(state.db, run.id)

        steps =
          Map.new(steps, fn {step_id, step_external_id, parent_id, repository, target, type,
                             memo_key, requires_tag_set_id, created_at} ->
            {:ok, executions} = Runs.get_step_executions(state.db, step_id)
            {:ok, arguments} = Runs.get_step_arguments(state.db, step_id)

            requires =
              if requires_tag_set_id do
                case TagSets.get_tag_set(state.db, requires_tag_set_id) do
                  {:ok, requires} -> requires
                end
              else
                %{}
              end

            arguments = Enum.map(arguments, &build_value(&1, state.db))

            {step_external_id,
             %{
               repository: repository,
               target: target,
               type: type,
               parent_id: parent_id,
               memo_key: memo_key,
               created_at: created_at,
               arguments: arguments,
               requires: requires,
               executions:
                 Map.new(executions, fn {execution_id, attempt, environment_id, execute_after,
                                         created_at, _session_id, assigned_at} ->
                   # TODO: load assets in one query
                   {:ok, asset_ids} = Results.get_assets_for_execution(state.db, execution_id)
                   assets = Map.new(asset_ids, &{&1, resolve_asset(state.db, &1)})

                   {:ok, dependencies} =
                     Runs.get_dependencies(state.db, execution_id)

                   # TODO: batch? get `get_result_dependencies` to resolve?
                   dependencies =
                     Map.new(dependencies, fn {dependency_id} ->
                       {dependency_id, resolve_execution(state.db, dependency_id)}
                     end)

                   {result, completed_at} =
                     case Results.get_result(state.db, execution_id) do
                       {:ok, {result, completed_at}} ->
                         {result, completed_at}

                       {:ok, nil} ->
                         {nil, nil}
                     end

                   result = build_result(result, state.db)

                   {:ok, children} =
                     Runs.get_execution_children(state.db, execution_id)

                   {attempt,
                    %{
                      execution_id: execution_id,
                      environment_id: environment_id,
                      created_at: created_at,
                      execute_after: execute_after,
                      assigned_at: assigned_at,
                      completed_at: completed_at,
                      assets: assets,
                      dependencies: dependencies,
                      result: result,
                      children: children,
                      log_count: Map.get(log_counts, execution_id, 0)
                    }}
                 end)
             }}
          end)

        {:ok, ref, state} = add_listener(state, {:run, run.id}, pid)
        {:reply, {:ok, run, parent, steps, ref}, state}
    end
  end

  def handle_call({:subscribe_logs, external_run_id, pid}, _from, state) do
    case Runs.get_run_by_external_id(state.db, external_run_id) do
      {:ok, run} ->
        case Observations.get_messages_for_run(state.db, run.id) do
          {:ok, messages} ->
            messages =
              Enum.map(messages, fn {execution_id, timestamp, level, template, values} ->
                {execution_id, timestamp, level, template,
                 Map.new(values, fn {k, v} -> {k, build_value(v, state.db)} end)}
              end)

            {:ok, ref, state} = add_listener(state, {:logs, run.id}, pid)
            {:reply, {:ok, ref, messages}, state}
        end
    end
  end

  def handle_call({:subscribe_targets, environment_id, pid}, _from, state) do
    # TODO: indicate which are archived (only workflows/sensors)
    {:ok, workflows, sensors} =
      Manifests.get_all_targets_for_environment(state.db, environment_id)

    {:ok, steps} = Runs.get_steps_for_environment(state.db, environment_id)

    result =
      Enum.reduce(
        %{workflow: workflows, sensor: sensors},
        %{},
        fn {target_type, targets}, result ->
          Enum.reduce(targets, result, fn {repository_name, target_names}, result ->
            Enum.reduce(target_names, result, fn target_name, result ->
              put_in(
                result,
                [Access.key(repository_name, %{}), target_name],
                {target_type, nil}
              )
            end)
          end)
        end
      )

    result =
      Enum.reduce(
        steps,
        result,
        fn {repository_name, target_name, target_type, run_external_id, step_external_id, attempt},
           result ->
          put_in(
            result,
            [Access.key(repository_name, %{}), target_name],
            {target_type, {run_external_id, step_external_id, attempt}}
          )
        end
      )

    {:ok, ref, state} = add_listener(state, {:targets, environment_id}, pid)
    {:reply, {:ok, result, ref}, state}
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
      state =
        state
        |> remove_session(session_id)
        |> flush_notifications()

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

    executions =
      Enum.filter(executions, fn execution ->
        state.environments[execution.environment_id].status == :active
      end)

    now = System.os_time(:millisecond)

    {executions_due, executions_future, executions_defer} =
      split_executions(executions, now)

    state =
      executions_defer
      |> Enum.reverse()
      |> Enum.reduce(state, fn {execution_id, defer_id, _run_id, repository}, state ->
        case record_and_notify_result(
               state,
               execution_id,
               {:deferred, defer_id},
               repository
             ) do
          {:ok, state} -> state
          {:error, :already_recorded} -> state
        end
      end)

    tag_sets =
      executions_due
      |> Enum.map(& &1.requires_tag_set_id)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn tag_set_id, tag_sets ->
        if tag_set_id do
          case TagSets.get_tag_set(state.db, tag_set_id) do
            {:ok, tag_set} -> Map.put(tag_sets, tag_set_id, tag_set)
          end
        else
          tag_sets
        end
      end)

    {state, assigned, unassigned} =
      executions_due
      |> Enum.reverse()
      |> Enum.reduce(
        {state, [], []},
        fn
          execution, {state, assigned, unassigned} ->
            # TODO: support caching for other attempts?
            cached_execution_id =
              if execution.attempt == 1 && execution.cache_key do
                cache_environment_ids = get_cache_environment_ids(state, execution.environment_id)

                recorded_after =
                  if execution.cache_max_age, do: now - execution.cache_max_age, else: 0

                case Runs.find_cached_execution(
                       state.db,
                       cache_environment_ids,
                       execution.step_id,
                       execution.cache_key,
                       recorded_after
                     ) do
                  {:ok, cached_execution_id} ->
                    cached_execution_id
                end
              end

            if cached_execution_id do
              {:ok, state} =
                process_result(state, execution.execution_id, {:cached, cached_execution_id})

              {state, assigned, unassigned}
            else
              # TODO: choose session before resolving arguments?
              {:ok, arguments} =
                case Results.get_latest_checkpoint(state.db, execution.step_id) do
                  {:ok, nil} ->
                    Runs.get_step_arguments(state.db, execution.step_id)

                  {:ok, {checkpoint_id, _, _, _}} ->
                    Results.get_checkpoint_arguments(state.db, checkpoint_id)
                end

              if arguments_ready?(state.db, execution.wait_for, arguments) &&
                   dependencies_ready?(state.db, execution.execution_id) do
                requires =
                  if execution.requires_tag_set_id,
                    do: Map.fetch!(tag_sets, execution.requires_tag_set_id),
                    else: %{}

                if execution.type == :task || !execution.parent_id do
                  case choose_session(state, execution, requires) do
                    nil ->
                      {state, assigned, [execution | unassigned]}

                    session_id ->
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
                          {:execute, execution.execution_id, execution.repository,
                           execution.target, arguments}
                        )

                      {state, [{execution, assigned_at} | assigned], unassigned}
                  end
                else
                  state =
                    case schedule_run(
                           state,
                           execution.repository,
                           execution.target,
                           execution.type,
                           arguments,
                           execution.environment_id,
                           parent_id: execution.execution_id,
                           cache: execution.cache_key,
                           retries:
                             if(execution.retry_limit > 0,
                               do: %{
                                 limit: execution.retry_limit,
                                 delay_min: execution.retry_delay_min,
                                 delay_max: execution.retry_delay_max
                               }
                             ),
                           requires: requires
                         ) do
                      {:ok, _external_run_id, _external_step_id, spawned_execution_id, state} ->
                        {:ok, state} =
                          process_result(
                            state,
                            execution.execution_id,
                            {:spawned, spawned_execution_id}
                          )

                        state
                    end

                  {state, assigned, unassigned}
                end
              else
                {state, assigned, unassigned}
              end
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

    state =
      if Enum.any?(unassigned) do
        {:ok, latest_launches} = Launches.get_latest_launches(state.db)
        {:ok, pending_launches} = Launches.get_pending_launches(state.db)

        pending_launch_pool_ids =
          MapSet.new(pending_launches, fn {_, pool_id, _, _} ->
            pool_id
          end)

        now = System.os_time(:millisecond)

        unassigned
        |> Enum.group_by(& &1.environment_id)
        |> Enum.reduce(state, fn {environment_id, executions}, state ->
          executions
          |> Enum.map(fn execution ->
            requires =
              if execution.requires_tag_set_id,
                do: Map.fetch!(tag_sets, execution.requires_tag_set_id),
                else: %{}

            choose_pool(state, execution, requires)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.reject(&(&1 in pending_launch_pool_ids))
          |> Enum.filter(&(now - Map.get(latest_launches, &1, 0) > 10_000))
          |> Enum.reduce(state, fn pool_id, state ->
            case Launches.create_launch(state.db, pool_id) do
              {:ok, launch_id} ->
                launcher = state.environments[environment_id].pools[pool_id].launcher

                module =
                  case launcher.type do
                    :docker -> Coflux.DockerLauncher
                  end

                task =
                  Task.Supervisor.async_nolink(Coflux.LaunchSupervisor, module, :launch, [
                    state.project_id,
                    state.environments[environment_id].name,
                    launch_id,
                    Map.delete(launcher, :type)
                  ])

                put_in(state.launch_tasks[task.ref], launch_id)
            end
          end)
        end)
      else
        state
      end

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

  def handle_info({task_ref, _result}, state) when is_map_key(state.launch_tasks, task_ref) do
    launch_id = Map.fetch!(state.launch_tasks, task_ref)
    {:ok, _} = Launches.create_launch_result(state.db, launch_id, 1)
    state = Map.update!(state, :launch_tasks, &Map.delete(&1, task_ref))
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    cond do
      Map.has_key?(state.agents, ref) ->
        {{^pid, session_id}, state} = pop_in(state.agents[ref])

        state =
          if Map.has_key?(state.sessions, session_id) do
            # TODO: (re-)schedule timer when receiving heartbeats?
            expire_timer =
              Process.send_after(self(), {:expire_session, session_id}, @session_timeout_ms)

            update_in(
              state,
              [Access.key(:sessions), session_id],
              &Map.merge(&1, %{agent: nil, expire_timer: expire_timer})
            )
          else
            state
          end

        state =
          state
          |> notify_agent(session_id)
          |> flush_notifications()

        {:noreply, state}

      Map.has_key?(state.listeners, ref) ->
        state = remove_listener(state, ref)
        {:noreply, state}

      Map.has_key?(state.launch_tasks, ref) ->
        launch_id = Map.fetch!(state.launch_tasks, ref)
        {:ok, _} = Launches.create_launch_result(state.db, launch_id, 0)
        state = Map.update!(state, :launch_tasks, &Map.delete(&1, ref))
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  def terminate(_reason, state) do
    Store.close(state.db)
  end

  defp lookup_environment_by_name(state, environment_name) do
    case Map.fetch(state.environment_names, environment_name) do
      {:ok, environment_id} ->
        environment = Map.fetch!(state.environments, environment_id)

        if environment.status != :archived do
          {:ok, environment_id, environment}
        else
          {:error, :environment_invalid}
        end

      :error ->
        {:error, :environment_invalid}
    end
  end

  defp lookup_environment_by_id(state, environment_id) do
    case Map.fetch(state.environments, environment_id) do
      {:ok, environment} ->
        # TODO: include environment? Map.fetch!(state.environments, environment_id)
        {:ok, environment}

      :error ->
        {:error, :environment_invalid}
    end
  end

  defp is_environment_ancestor?(state, maybe_ancestor_id, environment_id) do
    # TODO: avoid cycle?
    environment = Map.fetch!(state.environments, environment_id)

    cond do
      !environment.base_id ->
        false

      environment.base_id == maybe_ancestor_id ->
        true

      true ->
        is_environment_ancestor?(state, maybe_ancestor_id, environment.base_id)
    end
  end

  defp get_cache_environment_ids(state, environment_id, ids \\ []) do
    environment = Map.fetch!(state.environments, environment_id)

    if environment.base_id do
      get_cache_environment_ids(state, environment.base_id, [environment_id | ids])
    else
      [environment_id | ids]
    end
  end

  defp remove_session(state, session_id) do
    {session, state} = pop_in(state.sessions[session_id])

    session.executing
    |> MapSet.union(session.starting)
    |> Enum.reduce(state, fn execution_id, state ->
      {:ok, state} = process_result(state, execution_id, :abandoned)
      state
    end)
    |> Map.update!(:targets, fn all_targets ->
      Enum.reduce(
        session.targets,
        all_targets,
        fn {repository_name, repository_targets}, all_targets ->
          Enum.reduce(repository_targets, all_targets, fn target_name, all_targets ->
            repository = Map.fetch!(all_targets, repository_name)
            target = Map.fetch!(repository, target_name)
            target = Map.update!(target, :session_ids, &MapSet.delete(&1, session_id))

            if Enum.empty?(target.session_ids) do
              repository = Map.delete(repository, target_name)

              if Enum.empty?(repository) do
                Map.delete(all_targets, repository_name)
              else
                Map.put(all_targets, repository_name, repository)
              end
            else
              repository = Map.put(repository, target_name, target)
              Map.put(all_targets, repository_name, repository)
            end
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
  end

  defp lookup_launch(state, launch_id, expected_environment_id) do
    if is_nil(launch_id) do
      {:ok, nil, nil}
    else
      case Launches.get_launch_by_id(state.db, launch_id) do
        {:ok, nil} ->
          {:error, :no_launch}

        {:ok, {pool_id, environment_id}} ->
          if environment_id == expected_environment_id do
            {:ok, launch_id, pool_id}
          else
            {:error, :no_launch}
          end
      end
    end
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

  defp schedule_run(state, repository, target_name, type, arguments, environment_id, opts) do
    cache_environment_ids = get_cache_environment_ids(state, environment_id)

    case Runs.schedule_run(
           state.db,
           repository,
           target_name,
           type,
           arguments,
           environment_id,
           cache_environment_ids,
           opts
         ) do
      {:ok, external_run_id, external_step_id, execution_id, attempt, created_at, child_added} ->
        state =
          if child_added do
            parent_id = Keyword.fetch!(opts, :parent_id)
            # TODO: avoid looking this up again?
            {:ok, parent_step} = Runs.get_step_for_execution(state.db, parent_id)

            notify_listeners(
              state,
              {:run, parent_step.run_id},
              {:child, parent_id,
               {external_run_id, external_step_id, repository, target_name, type}}
            )
          else
            state
          end

        # TODO: neater way to get execute_after?
        execute_after = Keyword.get(opts, :execute_after)
        execute_at = execute_after || created_at

        state =
          notify_listeners(
            state,
            case type do
              :workflow -> {:workflow, repository, target_name, environment_id}
              :sensor -> {:sensor, repository, target_name, environment_id}
            end,
            {:run, external_run_id, created_at}
          )
          |> notify_listeners(
            {:repositories, environment_id},
            {:scheduled, repository, execution_id, execute_at}
          )
          |> notify_listeners(
            {:repository, repository, environment_id},
            {:scheduled, execution_id, target_name, external_run_id, external_step_id, attempt,
             execute_after, created_at}
          )
          |> notify_listeners(
            {:targets, environment_id},
            {:step, repository, target_name, type, external_run_id, external_step_id, attempt}
          )

        {:ok, external_run_id, external_step_id, execution_id, state}
    end
  end

  defp rerun_step(state, step, environment_id, opts \\ []) do
    execute_after = Keyword.get(opts, :execute_after, nil)
    dependency_ids = Keyword.get(opts, :dependency_ids, [])

    # TODO: only get run if needed for notify?
    {:ok, run} = Runs.get_run_by_id(state.db, step.run_id)

    case Runs.rerun_step(state.db, step.id, environment_id, execute_after, dependency_ids) do
      {:ok, execution_id, attempt, created_at} ->
        {:ok, {run_repository, run_target}} = Runs.get_run_target(state.db, run.id)

        execute_at = execute_after || created_at

        state =
          state
          |> notify_listeners(
            {:run, step.run_id},
            {:execution, step.external_id, attempt, execution_id, environment_id, created_at,
             execute_after}
          )
          |> notify_listeners(
            {:repositories, environment_id},
            {:scheduled, step.repository, execution_id, execute_at}
          )
          |> notify_listeners(
            {:repository, step.repository, environment_id},
            {:scheduled, execution_id, step.target, run.external_id, step.external_id, attempt,
             execute_after, created_at}
          )
          |> notify_listeners(
            {:targets, environment_id},
            {:step, step.repository, step.target, run.external_id, step.external_id, attempt}
          )

        state =
          case step.type do
            :workflow ->
              notify_listeners(
                state,
                {:workflow, run_repository, run_target, environment_id},
                {:run, run.external_id, run.created_at}
              )

            :sensor ->
              notify_listeners(
                state,
                {:sensor, run_repository, run_target, environment_id},
                {:run, run.external_id, run.created_at}
              )

            _other ->
              state
          end

        send(self(), :execute)

        {:ok, execution_id, attempt, state}
    end
  end

  defp result_retryable?(result) do
    case result do
      {:error, _, _, _} -> true
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

  defp resolve_asset(db, asset_id) do
    {:ok, {type, path, blob_key, size, metadata}} =
      Results.get_asset_by_id(db, asset_id, true)

    %{
      type: type,
      path: path,
      metadata: metadata,
      blob_key: blob_key,
      size: size
    }
  end

  defp resolve_references(db, references) do
    Enum.map(references, fn
      {:fragment, serialiser, blob_key, size, metadata} ->
        {:fragment, serialiser, blob_key, size, metadata}

      {:execution, execution_id} ->
        {:execution, execution_id, resolve_execution(db, execution_id)}

      {:asset, asset_id} ->
        {:asset, asset_id, resolve_asset(db, asset_id)}
    end)
  end

  defp build_value(value, db) do
    case value do
      {:raw, data, references} ->
        {:raw, data, resolve_references(db, references)}

      {:blob, key, size, references} ->
        {:blob, key, size, resolve_references(db, references)}
    end
  end

  defp is_result_final?(result) do
    case result do
      {:error, _, _, _, retry_id} -> is_nil(retry_id)
      {:value, _} -> true
      {:abandoned, retry_id} -> is_nil(retry_id)
      :cancelled -> true
      {:suspended, successor_id} when not is_nil(successor_id) -> true
      {:deferred, execution_id} when not is_nil(execution_id) -> true
      {:cached, execution_id} when not is_nil(execution_id) -> true
      {:spawned, execution_id} when not is_nil(execution_id) -> true
    end
  end

  defp build_result(result, db) do
    case result do
      {:error, type, message, frames, retry_id} ->
        retry = if retry_id, do: resolve_execution(db, retry_id)
        {:error, type, message, frames, retry}

      {:value, value} ->
        {:value, build_value(value, db)}

      {:abandoned, retry_id} ->
        retry = if retry_id, do: resolve_execution(db, retry_id)
        {:abandoned, retry}

      :cancelled ->
        :cancelled

      {:suspended, successor_id} ->
        successor = if successor_id, do: resolve_execution(db, successor_id)
        {:suspended, successor}

      {type, execution_id} when type in [:deferred, :cached, :spawned] ->
        execution_result =
          case resolve_result(db, execution_id) do
            {:ok, execution_result} -> execution_result
            {:pending, _execution_id} -> nil
          end

        {type, resolve_execution(db, execution_id), build_result(execution_result, db)}

      nil ->
        nil
    end
  end

  # TODO: remove 'repository' argument?
  defp record_and_notify_result(state, execution_id, result, repository) do
    {:ok, environment_id} = Runs.get_environment_id_for_execution(state.db, execution_id)
    {:ok, successors} = Runs.get_result_successors(state.db, execution_id)

    case Results.record_result(state.db, execution_id, result) do
      {:ok, created_at} ->
        state = notify_waiting(state, execution_id)

        final = is_result_final?(result)
        result = build_result(result, state.db)

        state =
          successors
          |> Enum.reduce(state, fn {run_id, successor_id}, state ->
            cond do
              successor_id == execution_id ->
                notify_listeners(
                  state,
                  {:run, run_id},
                  {:result, execution_id, result, created_at}
                )

              final ->
                notify_listeners(
                  state,
                  {:run, run_id},
                  # TODO: better name?
                  {:result_result, successor_id, result, created_at}
                )

              true ->
                state
            end
          end)
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

  defp process_result(state, execution_id, result) do
    case Results.has_result?(state.db, execution_id) do
      {:ok, true} ->
        {:ok, state}

      {:ok, false} ->
        {:ok, step} = Runs.get_step_for_execution(state.db, execution_id)
        {:ok, environment_id} = Runs.get_environment_id_for_execution(state.db, execution_id)

        {retry_id, state} =
          cond do
            match?({:suspended, _, _}, result) ->
              {:suspended, execute_after, dependency_ids} = result

              # TODO: limit the number of times a step can suspend?

              {:ok, retry_id, _, state} =
                rerun_step(state, step, environment_id,
                  execute_after: execute_after,
                  dependency_ids: dependency_ids
                )

              state = abort_execution(state, execution_id)

              {retry_id, state}

            result_retryable?(result) && step.retry_limit > 0 ->
              {:ok, executions} = Runs.get_step_executions(state.db, step.id)

              attempts = Enum.count(executions)

              if attempts <= step.retry_limit do
                # TODO: add jitter (within min/max delay)
                delay_s =
                  step.retry_delay_min +
                    (attempts - 1) / step.retry_limit *
                      (step.retry_delay_max - step.retry_delay_min)

                execute_after = System.os_time(:millisecond) + delay_s * 1000
                # TODO: do cache lookup?
                {:ok, retry_id, _, state} =
                  rerun_step(state, step, environment_id, execute_after: execute_after)

                {retry_id, state}
              else
                {nil, state}
              end

            step.type == :sensor ->
              {:ok, executions} = Runs.get_step_executions(state.db, step.id)

              if Enum.all?(executions, &elem(&1, 5)) do
                now = System.os_time(:millisecond)

                last_assigned_at =
                  executions |> Enum.map(&elem(&1, 6)) |> Enum.max(&>=/2, fn -> nil end)

                execute_after =
                  if last_assigned_at && now - last_assigned_at < @sensor_rate_limit_ms do
                    last_assigned_at + @sensor_rate_limit_ms
                  end

                {:ok, _, _, state} =
                  rerun_step(state, step, environment_id, execute_after: execute_after)

                {nil, state}
              else
                {nil, state}
              end

            true ->
              {nil, state}
          end

        result =
          case result do
            {:error, type, message, frames} -> {:error, type, message, frames, retry_id}
            :abandoned -> {:abandoned, retry_id}
            {:suspended, _, _} -> {:suspended, retry_id}
            other -> other
          end

        state =
          case record_and_notify_result(
                 state,
                 execution_id,
                 result,
                 step.repository
               ) do
            {:ok, state} -> state
          end

        {:ok, state}
    end
  end

  defp resolve_result(db, execution_id) do
    # TODO: check execution exists?
    case Results.get_result(db, execution_id) do
      {:ok, nil} ->
        {:pending, execution_id}

      {:ok, {result, _}} ->
        case result do
          {:error, _, _, _, execution_id} when not is_nil(execution_id) ->
            resolve_result(db, execution_id)

          {:abandoned, execution_id} when not is_nil(execution_id) ->
            resolve_result(db, execution_id)

          {:deferred, execution_id} ->
            resolve_result(db, execution_id)

          {:cached, execution_id} ->
            resolve_result(db, execution_id)

          {:suspended, execution_id} ->
            resolve_result(db, execution_id)

          {:spawned, execution_id} ->
            resolve_result(db, execution_id)

          other ->
            {:ok, other}
        end
    end
  end

  defp assign_targets(state, targets, session_id) do
    Enum.reduce(targets, state, fn {repository, repository_targets}, state ->
      Enum.reduce(repository_targets, state, fn {type, target_names}, state ->
        Enum.reduce(target_names, state, fn target_name, state ->
          state
          |> update_in(
            [
              Access.key(:targets),
              Access.key(repository, %{}),
              Access.key(target_name, %{type: nil, session_ids: MapSet.new()})
            ],
            fn target ->
              target
              |> Map.put(:type, type)
              |> Map.update!(:session_ids, &MapSet.put(&1, session_id))
            end
          )
          |> update_in(
            [Access.key(:sessions), session_id, :targets, Access.key(repository, MapSet.new())],
            &MapSet.put(&1, target_name)
          )
        end)
      end)
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

  defp session_at_capacity?(session) do
    if session.concurrency != 0 do
      load = MapSet.size(session.starting) + MapSet.size(session.executing)
      load >= session.concurrency
    else
      false
    end
  end

  defp has_requirements?(provides, requires) do
    # TODO: case insensitive matching?
    Enum.all?(requires, fn {key, requires_values} ->
      (provides || %{})
      |> Map.get(key, [])
      |> Enum.any?(&(&1 in requires_values))
    end)
  end

  defp arguments_ready?(db, wait_for, arguments) do
    Enum.all?(wait_for, fn index ->
      references =
        case Enum.at(arguments, index) do
          {:raw, _, references} -> references
          {:blob, _, _, references} -> references
          nil -> []
        end

      Enum.all?(references, fn
        {:execution, execution_id} ->
          case resolve_result(db, execution_id) do
            {:ok, _} -> true
            {:pending, _} -> false
          end

        {:fragment, _serialiser, _blob_key, _size, _metadata} ->
          true

        {:asset, _asset_id} ->
          true
      end)
    end)
  end

  defp dependencies_ready?(db, execution_id) do
    # TODO: also check assets?
    case Runs.get_dependencies(db, execution_id) do
      {:ok, dependencies} ->
        Enum.all?(dependencies, fn {dependency_id} ->
          case resolve_result(db, dependency_id) do
            {:ok, _} -> true
            {:pending, _} -> false
          end
        end)
    end
  end

  defp choose_session(state, execution, requires) do
    target =
      state.targets
      |> Map.get(execution.repository, %{})
      |> Map.get(execution.target)

    if target && target.type == execution.type do
      session_ids =
        Enum.filter(target.session_ids, fn session_id ->
          session = Map.fetch!(state.sessions, session_id)

          session.environment_id == execution.environment_id && session.agent &&
            not session_at_capacity?(session) &&
            has_requirements?(session.provides, requires)
        end)

      if Enum.any?(session_ids) do
        # TODO: prioritise (based on 'cost'?)
        Enum.random(session_ids)
      end
    end
  end

  defp choose_pool(state, execution, requires) do
    pools =
      state.environments
      |> Map.fetch!(execution.environment_id)
      |> Map.fetch!(:pools)
      |> Map.filter(fn {_, pool} ->
        # TODO: match repositories
        pool.launcher && has_requirements?(pool.provides, requires)
      end)

    if Enum.any?(pools) do
      pools |> Map.keys() |> Enum.random()
    end
  end

  defp notify_waiting(state, execution_id) do
    {execution_waiting, waiting} = Map.pop(state.waiting, execution_id)

    if execution_waiting do
      case resolve_result(state.db, execution_id) do
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

  defp filter_execution_children(execution_id, executions) do
    execution = Enum.find(executions, &(elem(&1, 0) == execution_id))
    # TODO: handle execution not found?

    children =
      executions
      |> Enum.filter(&(elem(&1, 1) == execution_id))
      |> Enum.flat_map(&filter_execution_children(elem(&1, 0), executions))

    [execution | children]
  end
end

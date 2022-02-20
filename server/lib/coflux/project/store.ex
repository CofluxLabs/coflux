defmodule Coflux.Project.Store do
  alias Coflux.Project.Models
  alias Coflux.Repo.Projects, as: Repo

  import Ecto.Query, only: [from: 2]

  def list_manifests(project_id, environment_id) do
    query =
      from(
        m in Models.Manifest,
        left_join: sm in Models.SessionManifest,
        on: sm.manifest_id == m.id,
        left_join: s in Models.Session,
        on: s.id == sm.session_id,
        where: s.environment_id == ^environment_id,
        distinct: [m.id],
        order_by: [m.id, desc: sm.created_at],
        select: {m, sm}
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def list_task_runs(project_id, repository, target, environment_id) do
    query =
      from(r in Models.Run,
        join: s in Models.Step,
        on: s.run_id == r.id,
        where: is_nil(s.parent_attempt) and s.repository == ^repository and s.target == ^target,
        where: r.environment_id == ^environment_id,
        order_by: [desc: r.created_at]
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_latest_task_run(project_id, repository, target, environment_id) do
    query =
      from(r in Models.Run,
        join: s in Models.Step,
        on: s.run_id == r.id,
        where: is_nil(s.parent_attempt) and s.repository == ^repository and s.target == ^target,
        where: r.environment_id == ^environment_id,
        order_by: [desc: r.created_at],
        limit: 1
      )

    {:ok, Repo.one(query, prefix: project_id)}
  end

  def get_manifest(project_id, manifest_id) do
    {:ok, Repo.get!(Models.Manifest, manifest_id, prefix: project_id)}
  end

  def find_manifest(project_id, repository, environment_id) do
    query =
      from(
        m in Models.Manifest,
        left_join: sm in Models.SessionManifest,
        on: sm.manifest_id == m.id,
        left_join: s in Models.Session,
        on: s.id == sm.session_id,
        where: m.repository == ^repository,
        where: s.environment_id == ^environment_id,
        order_by: [desc: sm.created_at],
        limit: 1
      )

    case Repo.one(query, prefix: project_id) do
      nil -> {:error, :not_found}
      manifest -> {:ok, manifest}
    end
  end

  def get_run(project_id, run_id) do
    case Repo.get(Models.Run, run_id, prefix: project_id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  def get_steps(project_id, run_id, step_ids \\ nil) do
    query = from(s in Models.Step, where: s.run_id == ^run_id)
    query = if step_ids, do: from(s in query, where: s.id in ^step_ids), else: query
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_attempts(project_id, run_id) do
    query = from(a in Models.Attempt, where: a.run_id == ^run_id)
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_dependencies(project_id, execution_ids) do
    query = from(d in Models.Dependency, where: d.execution_id in ^execution_ids)
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_assignments(project_id, execution_ids) do
    query = from(a in Models.Assignment, where: a.execution_id in ^execution_ids)
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_results(project_id, execution_ids) do
    query = from(r in Models.Result, where: r.execution_id in ^execution_ids)
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_execution_runs(project_id, execution_ids) do
    query = from(r in Models.Run, where: r.execution_id in ^execution_ids)
    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_run_initial_step(project_id, run_id) do
    query = from(s in Models.Step, where: s.run_id == ^run_id and is_nil(s.parent_attempt))

    case Repo.one(query, prefix: project_id) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  def get_step_latest_attempt(project_id, run_id, step_id) do
    query =
      from(a in Models.Attempt,
        where: a.run_id == ^run_id and a.step_id == ^step_id,
        order_by: [desc: :number],
        limit: 1
      )

    case Repo.one(query, prefix: project_id) do
      nil -> {:error, :not_found}
      attempt -> {:ok, attempt}
    end
  end

  def create_session(project_id, environment_id) do
    case Repo.insert(
           %Models.Session{environment_id: environment_id, created_at: DateTime.utc_now()},
           prefix: project_id
         ) do
      {:ok, session} ->
        {:ok, session.id}
    end
  end

  def get_session(project_id, session_id) do
    {:ok, Repo.get!(Models.Session, session_id, prefix: project_id)}
  end

  def list_environments(project_id) do
    # TODO: just list recently used?
    {:ok, Repo.all(Models.Environment, prefix: project_id)}
  end

  def get_environment(project_id, environment_id) do
    case Repo.get(Models.Environment, environment_id, prefix: project_id) do
      nil -> {:error, :not_found}
      environment -> {:ok, environment}
    end
  end

  def get_environment_by_name(project_id, name, opts \\ []) do
    case Repo.get_by(Models.Environment, [name: name], prefix: project_id) do
      nil ->
        if opts[:create] do
          with {:error, _} <-
                 Repo.insert(%Models.Environment{name: name, created_at: DateTime.utc_now()},
                   prefix: project_id
                 ) do
            {:ok, Repo.get_by!(Models.Environment, [name: name], prefix: project_id)}
          end
        else
          :error
        end

      environment ->
        {:ok, environment}
    end
  end

  def register_targets(project_id, session_id, repository, version, targets) do
    now = DateTime.utc_now()

    tasks =
      targets
      |> Enum.filter(fn {_target, config} -> config.type == :task end)
      |> Map.new(fn {target, config} ->
        {target, config.parameters}
      end)

    sensors =
      targets
      |> Enum.filter(fn {_target, config} -> config.type == :sensor end)
      |> Enum.map(fn {target, _config} -> target end)

    hash = hash_manifest(repository, version, tasks, sensors)

    Repo.transaction(fn ->
      # TODO: get id on conflict?
      manifest =
        Repo.insert!(
          %Models.Manifest{
            repository: repository,
            version: version,
            hash: hash,
            tasks: tasks,
            sensors: sensors,
            created_at: now
          },
          prefix: project_id,
          on_conflict: :nothing
        )

      manifest_id =
        if manifest.id do
          manifest.id
        else
          Repo.get_by!(Models.Manifest, [hash: hash], prefix: project_id).id
        end

      Repo.insert!(
        %Models.SessionManifest{
          session_id: session_id,
          manifest_id: manifest_id,
          created_at: now
        },
        prefix: project_id
      )

      hash
    end)
  end

  def schedule_task(project_id, environment_id, repository, target, arguments, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :version)
    execution_id = Keyword.get(opts, :execution_id)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    Repo.transaction(fn ->
      now = DateTime.utc_now()

      # TODO: hash key with (some?) task details
      existing_run =
        idempotency_key &&
          Repo.get_by(Models.Run, [idempotency_key: idempotency_key], prefix: project_id)

      if existing_run do
        existing_run.id
      else
        run =
          Repo.insert!(
            %Models.Run{
              id: Base.encode32(:rand.bytes(10)),
              environment_id: environment_id,
              execution_id: execution_id,
              idempotency_key: idempotency_key,
              created_at: now
            },
            prefix: project_id
          )

        do_schedule_step(project_id, run, repository, target, arguments,
          now: now,
          environment_id: environment_id,
          priority: priority,
          version: version
        )

        run.id
      end
    end)
  end

  def schedule_step(
        project_id,
        environment_id,
        from_execution_id,
        repository,
        target,
        arguments,
        opts \\ []
      ) do
    priority = Keyword.get(opts, :priority, 0)
    version = Keyword.get(opts, :version)
    cache_key = Keyword.get(opts, :cache_key)

    Repo.transaction(fn ->
      from_attempt =
        Repo.get_by!(Models.Attempt, [execution_id: from_execution_id], prefix: project_id)

      run = Repo.get!(Models.Run, from_attempt.run_id, prefix: project_id)
      now = DateTime.utc_now()

      execution_id =
        do_schedule_step(project_id, run, repository, target, arguments,
          now: now,
          environment_id: environment_id,
          priority: priority,
          version: version,
          parent_step_id: from_attempt.step_id,
          parent_attempt: from_attempt.number,
          cache_key: cache_key
        )

      execution_id
    end)
  end

  def rerun_step(project_id, run_id, step_id, opts \\ []) do
    version = Keyword.get(opts, :version)
    environment_id = Keyword.fetch!(opts, :environment_id)
    now = DateTime.utc_now()
    step = Repo.get_by!(Models.Step, [run_id: run_id, id: step_id], prefix: project_id)
    {:ok, last_attempt} = get_step_latest_attempt(project_id, run_id, step_id)
    number = last_attempt.number + 1

    execution =
      Repo.insert!(
        %Models.Execution{
          repository: step.repository,
          target: step.target,
          arguments: step.arguments,
          environment_id: environment_id,
          priority: step.priority,
          version: version,
          created_at: now
        },
        prefix: project_id
      )

    Repo.insert!(
      %Models.Attempt{
        run_id: step.run_id,
        step_id: step.id,
        number: number,
        execution_id: execution.id,
        created_at: now
      },
      prefix: project_id
    )

    {:ok, number}
  end

  def record_heartbeats(project_id, executions) do
    now = DateTime.utc_now()

    Repo.insert_all(
      Models.Heartbeat,
      Enum.map(executions, fn {execution_id, status} ->
        %{execution_id: execution_id, created_at: now, status: status}
      end),
      prefix: project_id
    )

    :ok
  end

  def list_pending_executions(project_id) do
    now = DateTime.utc_now()

    query =
      from(e in Models.Execution,
        left_join: a in Models.Assignment,
        on: a.execution_id == e.id,
        left_join: r in Models.Result,
        on: r.execution_id == e.id,
        where: e.execute_after <= ^now or is_nil(e.execute_after),
        where: is_nil(a.execution_id) and is_nil(r.execution_id),
        order_by: [desc: e.priority, asc: e.created_at]
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def list_running_executions(project_id) do
    query =
      from(e in Models.Execution,
        join: a in Models.Assignment,
        on: a.execution_id == e.id,
        left_join: r in Models.Result,
        on: r.execution_id == e.id,
        left_join: h in Models.Heartbeat,
        on: h.execution_id == e.id,
        where: is_nil(r.execution_id),
        distinct: [e.id],
        order_by: [desc: h.created_at],
        select: {e, a, h}
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def assign_execution(project_id, execution) do
    try_insert(project_id, Models.Assignment,
      execution_id: execution.id,
      created_at: DateTime.utc_now()
    )
  end

  def put_result(project_id, execution_id, result) do
    {type, value, extra} = parse_result(result)

    try_insert(project_id, Models.Result,
      execution_id: execution_id,
      type: type,
      value: value,
      extra: extra,
      created_at: DateTime.utc_now()
    )
  end

  def get_result(project_id, execution_id) do
    case Repo.get_by(Models.Result, [execution_id: execution_id], prefix: project_id) do
      nil -> {:error, :not_found}
      result -> {:ok, compose_result(result)}
    end
  end

  def put_cursor(project_id, execution_id, result) do
    {type, value} = parse_cursor(result)

    Repo.transaction(fn ->
      last_cursor = get_latest_cursor(project_id, execution_id)
      sequence = if(last_cursor, do: last_cursor.sequence + 1, else: 0)

      Repo.insert!(
        %Models.Cursor{
          execution_id: execution_id,
          sequence: sequence,
          type: type,
          value: value,
          created_at: DateTime.utc_now()
        },
        prefix: project_id
      )

      sequence
    end)
  end

  def record_dependency(project_id, from, to) do
    Repo.insert!(
      %Models.Dependency{
        execution_id: from,
        dependency_id: to,
        created_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      prefix: project_id
    )

    :ok
  end

  def activate_sensor(project_id, environment_id, repository, target) do
    Repo.transaction(fn ->
      activation =
        Repo.insert!(
          %Models.SensorActivation{
            repository: repository,
            target: target,
            environment_id: environment_id,
            created_at: DateTime.utc_now()
          },
          prefix: project_id
        )

      iterate_sensor(project_id, activation, nil)
      activation.id
    end)
  end

  def deactivate_sensor(project_id, activation_id) do
    now = DateTime.utc_now()

    {:ok, _} =
      Repo.transaction(fn ->
        query =
          from(si in Models.SensorIteration,
            left_join: r in Models.Result,
            on: r.execution_id == si.execution_id,
            where: si.activation_id == ^activation_id and is_nil(r.execution_id),
            order_by: [desc: si.sequence],
            limit: 1
          )

        iteration = Repo.one(query, prefix: project_id)

        Repo.insert!(
          %Models.SensorDeactivation{
            activation_id: activation_id,
            created_at: now
          },
          prefix: project_id
        )

        Repo.insert!(
          %Models.Result{
            execution_id: iteration.execution_id,
            type: 5,
            created_at: now
          },
          prefix: project_id
        )
      end)

    :ok
  end

  def list_sensor_activations(project_id) do
    query =
      from(sa in Models.SensorActivation,
        left_join: sd in Models.SensorDeactivation,
        on: sd.activation_id == sa.id,
        where: is_nil(sd.activation_id)
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def get_sensor_activation(project_id, activation_id) do
    case Repo.get(Models.SensorActivation, activation_id, prefix: project_id) do
      nil -> {:error, :not_found}
      activation -> {:ok, activation}
    end
  end

  def get_sensor_deactivation(project_id, activation_id) do
    case Repo.get_by(Models.SensorDeactivation, [activation_id: activation_id], prefix: project_id) do
      nil -> {:error, :not_found}
      deactivation -> {:ok, deactivation}
    end
  end

  def list_sensor_runs(project_id, activation_id) do
    query =
      from(r in Models.Run,
        join: e in Models.Execution,
        on: e.id == r.execution_id,
        join: si in Models.SensorIteration,
        on: si.execution_id == e.id,
        where: si.activation_id == ^activation_id,
        order_by: [desc: e.created_at],
        limit: 100
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def latest_sensor_execution(project_id, activation_id) do
    query =
      from(e in Models.Execution,
        join: si in Models.SensorIteration,
        on: si.execution_id == e.id,
        left_join: r in Models.Result,
        on: r.execution_id == e.id,
        where: si.activation_id == ^activation_id and is_nil(r.execution_id),
        order_by: [desc: si.sequence],
        limit: 1
      )

    case Repo.one(query, prefix: project_id) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  def list_pending_sensors(project_id) do
    query =
      from(sa in Models.SensorActivation,
        left_join: sd in Models.SensorDeactivation,
        on: sd.activation_id == sa.id,
        join: si in Models.SensorIteration,
        on: si.activation_id == sa.id,
        join: e in Models.Execution,
        on: e.id == si.execution_id,
        left_join: r in Models.Result,
        on: r.execution_id == e.id,
        where: is_nil(sd.activation_id),
        distinct: [sa.id],
        order_by: [desc: si.sequence],
        select: {sa, si, r}
      )

    {:ok, Repo.all(query, prefix: project_id)}
  end

  def iterate_sensor(project_id, activation, last_iteration) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      argument =
        if last_iteration do
          cursor = get_latest_cursor(project_id, last_iteration.execution_id)

          if cursor do
            compose_result(cursor)
          else
            {:json, nil}
          end
        else
          {:json, nil}
        end

      # TODO: support getting specific version from activation?
      execution =
        Repo.insert!(
          %Models.Execution{
            repository: activation.repository,
            target: activation.target,
            arguments: [argument],
            environment_id: activation.environment_id,
            priority: 0,
            created_at: now
          },
          prefix: project_id
        )

      last_sequence = if last_iteration, do: last_iteration.sequence, else: 0

      try_insert(project_id, Models.SensorIteration,
        activation_id: activation.id,
        sequence: last_sequence + 1,
        execution_id: execution.id,
        created_at: now
      )
    end)

    # TODO: return?
  end

  def log_message(project_id, execution_id, level, message) do
    Repo.insert!(
      %Models.LogMessage{
        execution_id: execution_id,
        level: level,
        message: message,
        created_at: DateTime.utc_now()
      },
      prefix: project_id
    )

    :ok
  end

  def get_log_messages(project_id, execution_ids) do
    messages =
      Repo.all(
        from(
          l in Models.LogMessage,
          where: l.execution_id in ^execution_ids,
          order_by: :created_at
        ),
        prefix: project_id
      )

    {:ok, messages}
  end

  defp parse_result(result) do
    case result do
      {:json, value} when is_binary(value) -> {0, value, nil}
      {:blob, key} when is_binary(key) -> {1, key, nil}
      {:result, execution_id} when is_binary(execution_id) -> {2, execution_id, nil}
      {:failed, error, stacktrace} -> {3, error, stacktrace}
      :abandoned -> {4, nil, nil}
    end
  end

  defp parse_cursor(result) do
    case result do
      {:json, value} when is_binary(value) -> {0, value}
      {:blob, key} when is_binary(key) -> {1, key}
    end
  end

  defp compose_result(result) do
    case result.type do
      0 -> {:json, result.value}
      1 -> {:blob, result.value}
      2 -> {:result, result.value}
      3 -> {:failed, result.value, result.extra}
      4 -> :abandoned
    end
  end

  defp do_schedule_step(project_id, run, repository, target, arguments, opts) do
    now = Keyword.fetch!(opts, :now)
    environment_id = Keyword.fetch!(opts, :environment_id)
    priority = Keyword.fetch!(opts, :priority)
    version = Keyword.fetch!(opts, :version)
    parent_step_id = Keyword.get(opts, :parent_step_id)
    parent_attempt = Keyword.get(opts, :parent_attempt)

    cache_key = Keyword.get(opts, :cache_key)

    cached_step =
      if cache_key do
        query =
          from(
            s in Models.Step,
            where: s.cache_key == ^cache_key,
            order_by: [desc: s.created_at],
            limit: 1
          )

        Repo.one(query, prefix: project_id)
      end

    step =
      Repo.insert!(
        %Models.Step{
          run_id: run.id,
          id: Base.encode32(:rand.bytes(5)),
          parent_step_id: parent_step_id,
          parent_attempt: parent_attempt,
          repository: repository,
          target: target,
          arguments: arguments,
          priority: priority,
          cache_key: unless(cached_step, do: cache_key),
          cached_run_id: if(cached_step, do: cached_step.run_id),
          cached_step_id: if(cached_step, do: cached_step.id),
          created_at: now
        },
        prefix: project_id
      )

    execution_id =
      if cached_step do
        # TODO: check result and handle failed execution? (create new step? and/or reschedule?)
        query =
          from(
            a in Models.Attempt,
            where: a.run_id == ^cached_step.run_id and a.step_id == ^cached_step.id,
            order_by: [desc: a.created_at],
            limit: 1
          )

        attempt = Repo.one!(query, prefix: project_id)
        attempt.execution_id
      else
        execution =
          Repo.insert!(
            %Models.Execution{
              repository: step.repository,
              target: step.target,
              arguments: step.arguments,
              environment_id: environment_id,
              priority: step.priority,
              version: version,
              created_at: now
            },
            prefix: project_id
          )

        Repo.insert!(
          %Models.Attempt{
            run_id: step.run_id,
            step_id: step.id,
            number: 1,
            execution_id: execution.id,
            created_at: now
          },
          prefix: project_id
        )

        execution.id
      end

    execution_id
  end

  defp try_insert(project_id, model, entry) do
    case Repo.insert_all(model, [entry], on_conflict: :nothing, prefix: project_id) do
      {0, nil} -> :error
      {1, nil} -> :ok
    end
  end

  defp hash_manifest(repository_name, version, tasks, sensors) do
    task_parts =
      tasks
      |> Enum.sort()
      |> Enum.flat_map(fn {target, parameters} ->
        [target | Enum.map(parameters, &[&1.name, &1.annotation || "", &1.default || ""])]
      end)

    content =
      [repository_name, version || ""]
      |> Enum.concat(task_parts)
      |> Enum.concat(Enum.sort(sensors))
      |> Enum.join("\0")

    :crypto.hash(:sha, content)
  end

  defp get_latest_cursor(project_id, execution_id) do
    query =
      from(c in Models.Cursor,
        where: c.execution_id == ^execution_id,
        order_by: [desc: :sequence],
        limit: 1
      )

    Repo.one(query, prefix: project_id)
  end
end

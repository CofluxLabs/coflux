defmodule Coflux.Project.Observer do
  use GenServer, restart: :transient

  alias Coflux.Project.Models
  alias Coflux.Project.Store
  alias Coflux.Listener

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, project_id, opts)
  end

  def init(project_id) do
    IO.puts("Observer started (#{project_id}).")
    :ok = Listener.subscribe(Coflux.ProjectsListener, project_id, self(), [
      Models.Manifest,
      Models.Run,
      Models.Step,
      Models.Attempt,
      Models.Assignment,
      Models.Result,
      Models.Dependency,
      Models.SensorActivation,
      Models.SensorDeactivation,
      Models.SensorIteration,
      Models.LogMessage
    ])
    # TODO: timeout
    {:ok,
     %{
       project_id: project_id,
       # topic → {value: ..., subscribers: {ref → pid}}
       topics: %{},
       # ref → topic
       subscribers: %{},
       # execution id → {:run, {run id, step id, attempt}} | {:sensor, activation_id}
       executions: %{}
     }}
  end

  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    case Map.get(state.topics, topic) do
      nil ->
        case load_topic(topic, state.project_id) do
          {:ok, value, executions} ->
            state =
              state
              |> put_in([:topics, topic], %{value: value, subscribers: %{ref => pid}})
              |> Map.update!(:executions, &Map.merge(&1, executions))
              |> put_in([:subscribers, ref], topic)

            {:reply, {:ok, ref, value}, state}

          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}
        end

      %{value: value} ->
        state =
          state
          |> update_in([:topics, topic, :subscribers], &Map.put(&1, ref, pid))
          |> put_in([:subscribers, ref], topic)

        {:reply, {:ok, ref, value}, state}
    end
  end

  def handle_call({:unsubscribe, ref}, _from, state) do
    state = unsubscribe(state, ref)
    Process.demonitor(ref)
    {:reply, :ok, state}
  end

  def handle_info({:insert, _ref, model}, state) do
    {:noreply, handle_insert(state, model)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, unsubscribe(state, ref)}
  end

  defp unsubscribe(state, ref) do
    {topic, state} = pop_in(state.subscribers[ref])
    update_in(state.topics[topic].subscribers, &Map.delete(&1, ref))
  end

  defp load_topic("repositories", project_id) do
    case Store.list_repositories(project_id) do
      {:ok, repositories} ->
        {:ok, repositories, %{}}
    end
  end

  defp load_topic("sensors", project_id) do
    result =
      case Store.list_sensor_activations(project_id) do
        {:ok, activations} ->
          Map.new(activations, fn activation ->
            {activation.id, Map.take(activation, [:repository, :target, :tags])}
          end)
      end

    {:ok, result, %{}}
  end

  defp load_topic("sensors." <> activation_id, project_id) do
    with {:ok, activation} <- Store.get_sensor_activation(project_id, activation_id),
         {:ok, deactivation} <- Store.get_sensor_deactivation(project_id, activation_id),
         {:ok, runs} <- Store.list_sensor_runs(project_id, activation_id) do
      runs =
        Map.new(runs, fn run ->
          {run.id, Map.take(run, [:id, :created_at])}
        end)

      sensor =
        activation
        |> Map.take([:repository, :target, :tags, :created_at])
        |> Map.put(:deactivated_at, if(deactivation, do: deactivation.created_at))
        |> Map.put(:runs, runs)

      executions =
        case Store.latest_sensor_execution(project_id, activation_id) do
          {:ok, %{id: execution_id}} -> %{execution_id => {:sensor, activation_id}}
          {:error, :not_found} -> %{}
        end

      {:ok, sensor, executions}
    end
  end

  defp load_topic("tasks." <> repository_target, project_id) do
    case String.split(repository_target, ":", parts: 2) do
      [repository, target] ->
        with {:ok, manifest} <- Store.get_manifest(project_id, repository),
             {:ok, runs} <- Store.list_task_runs(project_id, repository, target) do
          case Map.fetch(manifest.tasks, target) do
            {:ok, parameters} ->
              runs =
                Map.new(runs, fn run ->
                  {run.id, Map.take(run, [:id, :tags, :created_at])}
                end)

              task = %{
                repository: repository,
                version: manifest.version,
                target: target,
                parameters: parameters,
                runs: runs
              }

              {:ok, task, %{}}

            :error ->
              {:error, :not_found}
          end
        end

      _other ->
        {:error, :not_found}
    end
  end

  defp load_topic("runs." <> run_id, project_id) do
    with {:ok, run} <- Store.get_run(project_id, run_id),
         {:ok, steps} <- Store.get_steps(project_id, run_id),
         {:ok, attempts} <- Store.get_attempts(project_id, run_id),
         execution_ids = Enum.map(attempts, & &1.execution_id),
         {:ok, dependencies} <- Store.get_dependencies(project_id, execution_ids),
         {:ok, assignments} <- Store.get_assignments(project_id, execution_ids),
         {:ok, results} <- Store.get_results(project_id, execution_ids),
         {:ok, execution_runs} <- Store.get_execution_runs(project_id, execution_ids) do
      dependencies =
        dependencies
        |> Enum.group_by(& &1.execution_id)
        |> Map.new(fn {execution_id, dependencies} ->
          {execution_id, Enum.map(dependencies, & &1.dependency_id)}
        end)

      assigned_at = Map.new(assignments, &{&1.execution_id, &1.created_at})

      results = Map.new(results, &{&1.execution_id, Map.take(&1, [:type, :value, :created_at])})

      execution_runs =
        execution_runs
        |> Enum.group_by(& &1.execution_id)
        |> Map.new(fn {execution_id, runs} ->
          # TODO: include run details (repository/target; from task or step?)
          {execution_id, Enum.map(runs, & &1.id)}
        end)

      result =
        run
        |> Map.take([:id, :tags, :created_at])
        |> Map.put(
          :steps,
          Map.new(steps, fn step ->
            parent =
              if step.parent_step_id,
                do: %{step_id: step.parent_step_id, attempt: step.parent_attempt}

            cached =
              if step.cached_step_id,
                do: %{run_id: step.cached_run_id, step_id: step.cached_step_id}

            value =
              step
              |> Map.take([:repository, :target, :created_at])
              |> Map.put(:id, step.id)
              |> Map.put(:parent, parent)
              |> Map.put(:cached, cached)
              |> Map.put(:arguments, Enum.map(step.arguments, & &1))
              |> Map.put(
                :attempts,
                attempts
                |> Enum.filter(&(&1.step_id == step.id))
                |> Map.new(fn attempt ->
                  execution_id = attempt.execution_id

                  value =
                    attempt
                    |> Map.take([:created_at, :number, :execution_id])
                    |> Map.put(:dependency_ids, Map.get(dependencies, execution_id, []))
                    |> Map.put(:run_ids, Map.get(execution_runs, execution_id, []))
                    |> Map.put(:assigned_at, Map.get(assigned_at, execution_id))
                    |> Map.put(:result, Map.get(results, execution_id))

                  {attempt.number, value}
                end)
              )

            {step.id, value}
          end)
        )

      executions =
        Map.new(attempts, &{&1.execution_id, {:run, {&1.run_id, &1.step_id, &1.number}}})

      {:ok, result, executions}
    end
  end

  defp load_topic("logs." <> run_id, project_id) do
    with {:ok, attempts} <- Store.get_attempts(project_id, run_id),
         execution_ids = Enum.map(attempts, & &1.execution_id),
         {:ok, log_messages} <- Store.get_log_messages(project_id, execution_ids) do
      result =
        Map.new(log_messages, fn log_message ->
          {log_message.id, Map.take(log_message, [:execution_id, :level, :message, :created_at])}
        end)

      {:ok, result, %{}}
    end
  end

  defp update_topic(state, topic, fun) do
    case Map.fetch(state.topics, topic) do
      {:ok, %{value: value, subscribers: subscribers}} ->
        value
        |> fun.()
        |> List.wrap()
        |> Enum.reduce(state, fn {path, new_value}, state ->
          state =
            if is_nil(new_value) do
              {_, state} = pop_in(state, [:topics, topic, :value] ++ path)
              state
            else
              put_in(state, [:topics, topic, :value] ++ path, new_value)
            end

          notify_subscribers(subscribers, path, new_value)
          state
        end)

      :error ->
        state
    end
  end

  defp notify_subscribers(subscribers, path, new_value) do
    Enum.each(subscribers, fn {ref, pid} ->
      send(pid, {:update, ref, path, new_value})
    end)
  end

  defp handle_insert(state, %Models.Manifest{} = manifest) do
    manifest.tasks
    |> Enum.reduce(state, fn {target, parameters}, state ->
      update_topic(state, "tasks.#{manifest.repository}:#{target}", fn _task ->
        [{[:parameters], parameters}, {[:version], manifest.version}]
      end)
    end)
    |> update_topic("repositories", fn _repositories ->
      {[manifest.repository], Map.take(manifest, [:version, :tasks, :sensors])}
    end)
  end

  defp handle_insert(state, %Models.Run{} = run) do
    if run.execution_id do
      new_run_id = run.id

      case Map.get(state.executions, run.execution_id) do
        nil ->
          state

        {:run, {run_id, step_id, attempt}} ->
          update_topic(state, "runs.#{run_id}", fn run ->
            run_ids = run.steps[step_id].attempts[attempt].run_ids

            if new_run_id not in run_ids do
              {[:steps, step_id, :attempts, attempt, :run_ids], [new_run_id | run_ids]}
            end
          end)

        {:sensor, activation_id} ->
          update_topic(state, "sensors.#{activation_id}", fn _sensor ->
            # TODO: limit number of runs?
            {[:runs, run.id], Map.take(run, [:id, :created_at])}
          end)
      end
    else
      state
    end
  end

  defp handle_insert(state, %Models.Step{} = step) do
    state =
      if is_nil(step.parent_attempt) do
        task_id = "#{step.repository}:#{step.target}"

        update_topic(state, "tasks.#{task_id}", fn _task ->
          {[:runs, step.run_id], %{id: step.run_id, created_at: step.created_at}}
        end)
      else
        state
      end

    update_topic(state, "runs.#{step.run_id}", fn _run ->
      parent =
        if step.parent_step_id,
          do: %{step_id: step.parent_step_id, attempt: step.parent_attempt}

      cached =
        if step.cached_step_id,
          do: %{run_id: step.cached_run_id, step_id: step.cached_step_id}

      value =
        step
        |> Map.take([:repository, :target, :created_at])
        |> Map.put(:id, step.id)
        |> Map.put(:parent, parent)
        |> Map.put(:cached, cached)
        |> Map.put(:arguments, Enum.map(step.arguments, & &1))
        |> Map.put(:attempts, %{})

      {[:steps, step.id], value}
    end)
  end

  defp handle_insert(state, %Models.Attempt{} = attempt) do
    topic = "runs.#{attempt.run_id}"

    if Map.has_key?(state.topics, topic) do
      state
      |> put_in(
        [:executions, attempt.execution_id],
        {:run, {attempt.run_id, attempt.step_id, attempt.number}}
      )
      |> update_topic(topic, fn _run ->
        value =
          attempt
          |> Map.take([:created_at, :number, :execution_id])
          |> Map.put(:dependency_ids, [])
          |> Map.put(:run_ids, [])
          |> Map.put(:assigned_at, nil)
          |> Map.put(:result, nil)

        {[:steps, attempt.step_id, :attempts, attempt.number], value}
      end)
    else
      state
    end
  end

  defp handle_insert(state, %Models.Assignment{} = assignment) do
    case Map.get(state.executions, assignment.execution_id) do
      {:run, {run_id, step_id, attempt}} ->
        update_topic(state, "runs.#{run_id}", fn _run ->
          {[:steps, step_id, :attempts, attempt, :assigned_at], assignment.created_at}
        end)

      _other ->
        state
    end
  end

  defp handle_insert(state, %Models.Result{} = result) do
    # TODO: remove execution from state.executions

    case Map.get(state.executions, result.execution_id) do
      {:run, {run_id, step_id, attempt}} ->
        update_topic(state, "runs.#{run_id}", fn _run ->
          value = Map.take(result, [:type, :value, :created_at])
          {[:steps, step_id, :attempts, attempt, :result], value}
        end)

      _other ->
        state
    end
  end

  defp handle_insert(state, %Models.Dependency{} = dependency) do
    case Map.get(state.executions, dependency.execution_id) do
      {:run, {run_id, step_id, attempt}} ->
        update_topic(state, "runs.#{run_id}", fn run ->
          dependency_ids = run.steps[step_id].attempts[attempt].dependency_ids

          if dependency.dependency_id not in dependency_ids do
            {[:steps, step_id, :attempts, attempt, :dependency_ids],
             [dependency.dependency_id | dependency_ids]}
          end
        end)

      _other ->
        state
    end
  end

  defp handle_insert(state, %Models.SensorActivation{} = activation) do
    update_topic(state, "sensors", fn _sensors ->
      {[activation.id], Map.take(activation, [:repository, :target, :tags])}
    end)
  end

  defp handle_insert(state, %Models.SensorDeactivation{} = deactivation) do
    state
    |> update_topic("sensors", fn _sensors ->
      {[deactivation.activation_id], nil}
    end)
    |> update_topic("sensors.#{deactivation.activation_id}", fn _sensor ->
      {[:deactivated_at], deactivation.created_at}
    end)
  end

  defp handle_insert(state, %Models.SensorIteration{} = iteration) do
    put_in(state.executions[iteration.execution_id], {:sensor, iteration.activation_id})
  end

  defp handle_insert(state, %Models.LogMessage{} = log_message) do
    case Map.get(state.executions, log_message.execution_id) do
      {:run, {run_id, _step_id, _attempt}} ->
        update_topic(state, "logs.#{run_id}", fn _logs ->
          {[log_message.execution_id],
           Map.take(log_message, [:execution_id, :level, :message, :created_at])}
        end)

      _other ->
        state
    end
  end
end

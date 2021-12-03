defmodule Coflux.Project.Observer do
  use GenServer, restart: :transient

  alias Ecto.Changeset
  alias Coflux.Project.Models
  alias Coflux.Project.Store
  alias Coflux.Listener

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, project_id, opts)
  end

  def init(project_id) do
    IO.puts("Observer started (#{project_id}).")
    :ok = Listener.subscribe(Coflux.ProjectsListener, project_id, self())
    # TODO: timeout
    {:ok,
     %{
       project_id: project_id,
       # topic → {value: ..., subscribers: {ref → pid}}
       topics: %{},
       # ref → topic
       subscribers: %{},
       # execution id → {run id, step id, attempt}
       executions: %{}
     }}
  end

  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    {state, value} =
      case Map.get(state.topics, topic) do
        nil ->
          case load_topic(topic, state.project_id) do
            {:ok, value, executions} ->
              state =
                state
                |> put_in([:topics, topic], %{value: value, subscribers: %{ref => pid}})
                |> Map.update!(:executions, &Map.merge(&1, executions))

              {state, value}
          end

        %{value: value} ->
          state = update_in(state.topics[topic].subscribers, &Map.put(&1, ref, pid))
          {state, value}
      end

    state = put_in(state.subscribers[ref], topic)
    {:reply, {:ok, ref, value}, state}
  end

  def handle_call({:unsubscribe, ref}, _from, state) do
    state = unsubscribe(state, ref)
    Process.demonitor(ref)
    {:reply, :ok, state}
  end

  def handle_info({:insert, _ref, table, data}, state) do
    {:noreply, handle_insert(state, table, data)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, unsubscribe(state, ref)}
  end

  defp unsubscribe(state, ref) do
    {topic, state} = pop_in(state.subscribers[ref])
    update_in(state.topics[topic].subscribers, &Map.delete(&1, ref))
  end

  defp load_topic("tasks", project_id) do
    tasks =
      project_id
      |> Store.list_tasks()
      |> Map.new(&{&1.id, Map.take(&1, [:id, :repository, :version, :target, :parameters])})

    {:ok, tasks, %{}}
  end

  defp load_topic("tasks." <> task_id, project_id) do
    runs =
      project_id
      |> Store.list_task_runs(task_id)
      |> Map.new(fn run ->
        {run.id, Map.take(run, [:id, :tags, :created_at])}
      end)

    task =
      project_id
      |> Store.get_task(task_id)
      |> Map.take([:id, :repository, :version, :target, :parameters])
      |> Map.put(:runs, runs)

    {:ok, task, %{}}
  end

  defp load_topic("runs." <> run_id, project_id) do
    run = Store.get_run(project_id, run_id)
    task = Store.get_task(project_id, run.task_id)
    steps = Store.get_steps(project_id, run_id)
    attempts = Store.get_attempts(project_id, run_id)
    execution_ids = Enum.map(attempts, & &1.execution_id)

    dependencies =
      project_id
      |> Store.get_dependencies(execution_ids)
      |> Enum.group_by(& &1.execution_id)
      |> Map.new(fn {execution_id, dependencies} ->
        {execution_id, Enum.map(dependencies, & &1.dependency_id)}
      end)

    assigned_at =
      project_id
      |> Store.get_assignments(execution_ids)
      |> Map.new(&{&1.execution_id, &1.created_at})

    results =
      project_id
      |> Store.get_results(execution_ids)
      |> Map.new(&{&1.execution_id, Map.take(&1, [:type, :value, :created_at])})

    execution_runs =
      project_id
      |> Store.get_execution_runs(execution_ids)
      |> Enum.group_by(& &1.execution_id)
      |> Map.new(fn {execution_id, runs} ->
        # TODO: include run details (repository/target; from task or step?)
        {execution_id, Enum.map(runs, & &1.id)}
      end)

    result =
      run
      |> Map.take([:id, :tags, :created_at])
      |> Map.put(:task, Map.take(task, [:id, :repository, :target, :version]))
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
                  |> Map.take([:created_at, :number])
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

    executions = Map.new(attempts, &{&1.execution_id, {&1.run_id, &1.step_id, &1.number}})

    {:ok, result, executions}
  end

  defp update_topic(state, topic, fun) do
    case Map.fetch(state.topics, topic) do
      {:ok, %{value: value, subscribers: subscribers}} ->
        case fun.(value) do
          nil ->
            state

          {path, new_value} ->
            state = put_in(state, [:topics, topic, :value] ++ path, new_value)
            notify_subscribers(subscribers, path, new_value)
            state
        end

      :error ->
        state
    end
  end

  defp notify_subscribers(subscribers, path, new_value) do
    Enum.each(subscribers, fn {ref, pid} ->
      send(pid, {:update, ref, path, new_value})
    end)
  end

  defp load_model(type, data) do
    type
    |> struct()
    |> Changeset.cast(data, type.__schema__(:fields))
    |> Changeset.apply_changes()
  end

  defp handle_insert(state, :tasks, data) do
    task = load_model(Models.Task, data)

    update_topic(state, "tasks", fn _tasks ->
      {[task.id], Map.take(task, [:id, :repository, :version, :target, :parameters])}
    end)
  end

  defp handle_insert(state, :runs, data) do
    run = load_model(Models.Run, data)

    state =
      update_topic(state, "tasks.#{run.task_id}", fn _task ->
        {[:runs, run.id], Map.take(run, [:id, :created_at])}
      end)

    if run.execution_id do
      new_run_id = run.id

      case Map.get(state.executions, run.execution_id) do
        nil ->
          state

        {run_id, step_id, attempt} ->
          update_topic(state, "runs.#{run_id}", fn run ->
            run_ids = run.steps[step_id].attempts[attempt].run_ids

            if new_run_id not in run_ids do
              {[:steps, step_id, :attempts, attempt, :run_ids], [new_run_id | run_ids]}
            end
          end)
      end
    else
      state
    end
  end

  defp handle_insert(state, :steps, data) do
    step = load_model(Models.Step, data)

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

  defp handle_insert(state, :attempts, data) do
    attempt = load_model(Models.Attempt, data)

    topic = "runs.#{attempt.run_id}"

    if Map.has_key?(state.topics, topic) do
      state
      |> put_in(
        [:executions, attempt.execution_id],
        {attempt.run_id, attempt.step_id, attempt.number}
      )
      |> update_topic(topic, fn _run ->
        value =
          attempt
          |> Map.take([:created_at, :number])
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

  defp handle_insert(state, :executions, _data) do
    # TODO
    state
  end

  defp handle_insert(state, :assignments, data) do
    assignment = load_model(Models.Assignment, data)

    case Map.get(state.executions, assignment.execution_id) do
      nil ->
        state

      {run_id, step_id, attempt} ->
        update_topic(state, "runs.#{run_id}", fn _run ->
          {[:steps, step_id, :attempts, attempt, :assigned_at], assignment.created_at}
        end)
    end
  end

  defp handle_insert(state, :heartbeats, _data) do
    # TODO
    state
  end

  defp handle_insert(state, :results, data) do
    result = load_model(Models.Result, data)

    case Map.get(state.executions, result.execution_id) do
      nil ->
        state

      {run_id, step_id, attempt} ->
        # TODO: remove execution from state.executions
        update_topic(state, "runs.#{run_id}", fn _run ->
          value = Map.take(result, [:type, :value, :created_at])
          {[:steps, step_id, :attempts, attempt, :result], value}
        end)
    end
  end

  defp handle_insert(state, :dependencies, data) do
    dependency = load_model(Models.Dependency, data)

    case Map.get(state.executions, dependency.execution_id) do
      nil ->
        state

      {run_id, step_id, attempt} ->
        update_topic(state, "runs.#{run_id}", fn run ->
          dependency_ids = run.steps[step_id].attempts[attempt].dependency_ids

          if dependency.dependency_id not in dependency_ids do
            {[:steps, step_id, :attempts, attempt, :dependency_ids],
             [dependency.dependency_id | dependency_ids]}
          end
        end)
    end
  end
end

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
       subscribers: %{}
     }}
  end

  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    {state, value} =
      case Map.get(state.topics, topic) do
        nil ->
          case load_topic(topic, state.project_id) do
            {:ok, value} ->
              state = put_in(state.topics[topic], %{value: value, subscribers: %{ref => pid}})
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

    {:ok, tasks}
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

    {:ok, task}
  end

  defp load_topic("runs." <> run_id, project_id) do
    run = Store.get_run(project_id, run_id)
    task = Store.get_task(project_id, run.task_id)
    steps = Store.get_steps(project_id, run_id)
    executions = Store.get_executions(project_id, run_id)
    dependencies = Store.get_dependencies(project_id, run_id)
    assignments = Store.get_assignments(project_id, run_id)
    results = Store.get_results(project_id, run_id)

    result =
      run
      |> Map.take([:id, :tags, :created_at])
      |> Map.put(:task, Map.take(task, [:id, :repository, :target, :version]))
      |> Map.put(
        :steps,
        Map.new(steps, fn step ->
          step_id = Models.Step.id(step)

          value =
            step
            |> Map.take([:repository, :target, :created_at])
            |> Map.put(:id, step_id)
            |> Map.put(:parent_id, Models.Step.parent_id(step))
            |> Map.put(:cached_id, Models.Step.cached_id(step))
            |> Map.put(:arguments, Enum.map(step.arguments, & &1))
            |> Map.put(
              :executions,
              executions
              |> Enum.filter(&(&1.step_id == step.id))
              |> Map.new(fn execution ->
                execution_id = Models.Execution.id(execution)

                value =
                  execution
                  |> Map.take([:created_at, :attempt])
                  |> Map.put(:id, execution_id)
                  |> Map.put(
                    :dependency_ids,
                    dependencies
                    |> Enum.filter(&(&1.step_id == step.id && &1.attempt == execution.attempt))
                    |> Enum.map(&Models.Dependency.to_execution_id(&1))
                  )
                  |> Map.put(
                    :assigned_at,
                    Enum.find_value(
                      assignments,
                      &(&1.step_id == step.id && &1.attempt == execution.attempt &&
                          &1.created_at)
                    )
                  )
                  |> Map.put(
                    :result,
                    Enum.find_value(
                      results,
                      &(&1.step_id == step.id && &1.attempt == execution.attempt &&
                          Map.take(&1, [:type, :value, :created_at]))
                    )
                  )

                {execution_id, value}
              end)
            )

          {step_id, value}
        end)
      )

    {:ok, result}
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

    update_topic(state, "tasks.#{run.task_id}", fn _task ->
      {[:runs, run.id], Map.take(run, [:id, :created_at])}
    end)
  end

  defp handle_insert(state, :steps, data) do
    step = load_model(Models.Step, data)

    update_topic(state, "runs.#{step.run_id}", fn _run ->
      step_id = Models.Step.id(step)

      value =
        step
        |> Map.take([:repository, :target, :created_at])
        |> Map.put(:id, step_id)
        |> Map.put(:parent_id, Models.Step.parent_id(step))
        |> Map.put(:cached_id, Models.Step.cached_id(step))
        |> Map.put(:arguments, Enum.map(step.arguments, & &1))
        |> Map.put(:executions, %{})

      {[:steps, step_id], value}
    end)
  end

  defp handle_insert(state, :executions, data) do
    execution = load_model(Models.Execution, data)

    update_topic(state, "runs.#{execution.run_id}", fn _run ->
      step_id = Models.Execution.step_id(execution)
      execution_id = Models.Execution.id(execution)

      value =
        execution
        |> Map.take([:created_at, :attempt])
        |> Map.put(:id, execution_id)
        |> Map.put(:dependency_ids, [])
        |> Map.put(:assigned_at, nil)
        |> Map.put(:result, nil)

      {[:steps, step_id, :executions, execution_id], value}
    end)
  end

  defp handle_insert(state, :assignments, data) do
    assignment = load_model(Models.Assignment, data)

    update_topic(state, "runs.#{assignment.run_id}", fn _run ->
      step_id = Models.Assignment.step_id(assignment)
      execution_id = Models.Assignment.execution_id(assignment)
      {[:steps, step_id, :executions, execution_id, :assigned_at], assignment.created_at}
    end)
  end

  defp handle_insert(state, :heartbeats, _data) do
    # TODO
    state
  end

  defp handle_insert(state, :results, data) do
    result = load_model(Models.Result, data)

    update_topic(state, "runs.#{result.run_id}", fn _run ->
      step_id = Models.Result.step_id(result)
      execution_id = Models.Result.execution_id(result)
      value = Map.take(result, [:type, :value, :created_at])
      {[:steps, step_id, :executions, execution_id, :result], value}
    end)
  end

  defp handle_insert(state, :dependencies, data) do
    dependency = load_model(Models.Dependency, data)

    update_topic(state, "runs.#{dependency.run_id}", fn run ->
      step_id = Models.Dependency.from_step_id(dependency)
      execution_id = Models.Dependency.from_execution_id(dependency)
      dependency_id = Models.Dependency.to_execution_id(dependency)
      dependency_ids = run.steps[step_id].executions[execution_id].dependency_ids

      if dependency_id not in dependency_ids do
        {[:steps, step_id, :executions, execution_id, :dependency_ids],
         [dependency_id | dependency_ids]}
      end
    end)
  end
end

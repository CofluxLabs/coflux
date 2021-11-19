defmodule Coflux.Project.Observer do
  use GenServer, restart: :transient

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
       # run_id → task_id
       task_ids: %{},
       # step_id → run_id
       run_ids: %{},
       # execution_id → step_id
       step_ids: %{}
     }}
  end

  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    {state, value} =
      case Map.get(state.topics, topic) do
        nil ->
          case load_topic(topic, state.project_id) do
            {:ok, value, ids} ->
              state = put_in(state.topics[topic], %{value: value, subscribers: %{ref => pid}})

              state =
                Enum.reduce(ids, state, fn {key, key_ids}, state ->
                  update_in(state[key], &Map.merge(&1, key_ids))
                end)

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
      |> Enum.map(&Map.take(&1, [:id, :repository, :target, :version]))

    {:ok, tasks, %{}}
  end

  defp load_topic("tasks." <> task_id, project_id) do
    # TODO: combine queries?

    runs =
      project_id
      |> Store.list_task_runs(task_id)
      |> Enum.map(fn run ->
        run
        |> Map.take([:id])
        |> Map.put(:created_at, run.initial_step.created_at)
      end)

    task =
      project_id
      |> Store.get_task(task_id)
      |> Map.take([:id, :repository, :target, :version])
      |> Map.put(:runs, runs)

    ids = %{task_ids: Map.new(runs, &{&1.id, task_id})}
    {:ok, task, ids}
  end

  defp load_topic("runs." <> run_id, project_id) do
    run =
      project_id
      |> Store.get_run(run_id)
      |> Map.from_struct()

    ids = %{task_ids: %{run.id => run.task_id}, run_ids: %{}, step_ids: %{}}

    ids =
      Enum.reduce(run.steps, ids, fn step, ids ->
        ids = put_in(ids.run_ids[step.id], run.id)

        Enum.reduce(step.executions, ids, fn execution, ids ->
          put_in(ids.step_ids[execution.id], step.id)
        end)
      end)

    result =
      run
      |> Map.take([:id])
      |> Map.put(:task, Map.take(run.task, [:id, :repository, :target, :version]))
      |> Map.put(
        :steps,
        Enum.map(run.steps, fn step ->
          step
          |> Map.take([:id, :parent_id, :repository, :target, :created_at])
          |> Map.put(:cached_step, step.cached_step && Map.take(step.cached_step, [:id, :run_id]))
          # TODO: extract arguments
          |> Map.put(:arguments, Enum.map(step.arguments, & &1))
          |> Map.put(
            :executions,
            Enum.map(step.executions, fn execution ->
              execution
              |> Map.take([:id, :created_at])
              |> Map.put(:dependency_ids, Enum.map(execution.dependencies, & &1.dependency_id))
              |> Map.put(:assigned_at, execution.assignment && execution.assignment.created_at)
              |> Map.put(
                :result,
                execution.result && Map.take(execution.result, [:type, :value, :created_at])
              )
            end)
          )
        end)
      )

    {:ok, result, ids}
  end

  defp put_value(path, target, value) do
    case path do
      [] ->
        value

      [head] when is_number(head) ->
        List.insert_at(target, head, value)

      [head | tail] when is_atom(head) ->
        Map.update!(target, head, &put_value(tail, &1, value))

      [head | tail] when is_number(head) ->
        List.update_at(target, head, &put_value(tail, &1, value))
    end
  end

  defp update_topic(state, topic, fun) do
    case Map.fetch(state.topics, topic) do
      {:ok, %{value: value, subscribers: subscribers}} ->
        case fun.(value) do
          nil ->
            state

          {path, new_value} ->
            state =
              update_in(state.topics[topic].value, fn existing_value ->
                put_value(path, existing_value, new_value)
              end)

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

  defp handle_insert(state, :tasks, data) do
    update_topic(state, "tasks", fn tasks ->
      if !Enum.any?(tasks, &(&1.id == data.id)) do
        # TODO: order?
        index = Enum.count(tasks)
        {[index], Map.take(data, [:id, :repository, :version, :target])}
      end
    end)
  end

  defp handle_insert(state, :runs, data) do
    state =
      update_topic(state, "tasks.#{data.task_id}", fn task ->
        if !Enum.any?(task.runs, &(&1.id == data.id)) do
          run =
            data
            |> Map.take([:id])
            |> Map.put(:created_at, nil)

          # TODO: order?
          index = Enum.count(task.runs)
          {[:runs, index], run}
        end
      end)

    if Map.has_key?(state.topics, "tasks.#{data.task_id}") do
      put_in(state, [:task_ids, data.id], data.task_id)
    else
      state
    end
  end

  defp handle_insert(state, :steps, data) do
    state =
      case Map.fetch(state.task_ids, data.run_id) do
        {:ok, task_id} ->
          update_topic(state, "tasks.#{task_id}", fn task ->
            run_index = Enum.find_index(task.runs, &(&1.id == data.run_id))
            run = Enum.fetch!(task.runs, run_index)

            if is_nil(run.created_at) do
              {[:runs, run_index, :created_at], data.created_at}
            end
          end)

        :error ->
          state
      end

    state =
      update_topic(state, "runs.#{data.run_id}", fn run ->
        if !Enum.any?(run.steps, &(&1.id == data.id)) do
          # TODO: order?
          step =
            data
            |> Map.take([:id, :parent_id, :repository, :target, :created_at])
            # TODO: run_id
            |> Map.put(
              :cached_step,
              data.cached_step_id && %{id: data.cached_step_id, run_id: nil}
            )
            # TODO: compose arguments
            |> Map.put(:arguments, Enum.map(data.arguments, & &1))
            |> Map.put(:executions, [])

          index = Enum.count(run.steps)
          {[:steps, index], step}
        end
      end)

    if Map.has_key?(state.topics, "runs.#{data.run_id}") do
      put_in(state, [:run_ids, data.id], data.run_id)
    else
      state
    end
  end

  defp handle_insert(state, :executions, data) do
    case Map.fetch(state.run_ids, data.step_id) do
      {:ok, run_id} ->
        state
        |> update_topic("runs.#{run_id}", fn run ->
          step_index = Enum.find_index(run.steps, &(&1.id == data.step_id))
          step = Enum.fetch!(run.steps, step_index)

          if !Enum.any?(step.executions, &(&1.id == data.id)) do
            execution =
              data
              |> Map.take([:id, :created_at])
              |> Map.put(:dependency_ids, [])
              |> Map.put(:assigned_at, nil)
              |> Map.put(:result, nil)

            execution_index = Enum.count(step.executions)
            {[:steps, step_index, :executions, execution_index], execution}
          end
        end)
        |> put_in([:step_ids, data.id], data.step_id)

      :error ->
        state
    end
  end

  defp handle_insert(state, :assignments, data) do
    with {:ok, step_id} <- Map.fetch(state.step_ids, data.execution_id),
         {:ok, run_id} <- Map.fetch(state.run_ids, step_id) do
      update_topic(state, "runs.#{run_id}", fn run ->
        step_index = Enum.find_index(run.steps, &(&1.id == step_id))
        step = Enum.fetch!(run.steps, step_index)
        execution_index = Enum.find_index(step.executions, &(&1.id == data.execution_id))
        {[:steps, step_index, :executions, execution_index, :assigned_at], data.created_at}
      end)
    else
      :error ->
        state
    end
  end

  defp handle_insert(state, :heartbeats, _data) do
    # TODO
    state
  end

  defp handle_insert(state, :results, data) do
    with {:ok, step_id} <- Map.fetch(state.step_ids, data.execution_id),
         {:ok, run_id} <- Map.fetch(state.run_ids, step_id) do
      update_topic(state, "runs.#{run_id}", fn run ->
        result = Map.take(data, [:type, :value, :created_at])
        step_index = Enum.find_index(run.steps, &(&1.id == step_id))
        step = Enum.fetch!(run.steps, step_index)
        execution_index = Enum.find_index(step.executions, &(&1.id == data.execution_id))
        {[:steps, step_index, :executions, execution_index, :result], result}
      end)
    else
      :error ->
        state
    end
  end

  defp handle_insert(state, :dependencies, data) do
    with {:ok, step_id} <- Map.fetch(state.step_ids, data.execution_id),
         {:ok, run_id} <- Map.fetch(state.run_ids, step_id) do
      update_topic(state, "runs.#{run_id}", fn run ->
        step_index = Enum.find_index(run.steps, &(&1.id == step_id))
        step = Enum.fetch!(run.steps, step_index)
        execution_index = Enum.find_index(step.executions, &(&1.id == data.execution_id))
        execution = Enum.fetch!(step.executions, execution_index)

        if data.dependency_id not in execution.dependency_ids do
          dependency_index = Enum.count(execution.dependency_ids)

          {[:steps, step_index, :executions, execution_index, :dependency_ids, dependency_index],
           data.dependency_id}
        end
      end)
    else
      :error ->
        state
    end
  end
end

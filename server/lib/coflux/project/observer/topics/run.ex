defmodule Coflux.Project.Observer.Topics.Run do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [
      Models.Run,
      Models.Step,
      Models.Attempt,
      Models.Assignment,
      Models.Result,
      Models.Dependency
    ]

  def load(project_id, [run_id]) do
    with {:ok, run} <- Store.get_run(project_id, run_id),
         {:ok, environment} <- Store.get_environment(project_id, run.environment_id),
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
        |> Map.put(:environment, Map.take(environment, [:id, :name]))
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
              |> Map.put(:arguments, Enum.map(step.arguments, &compose_argument/1))
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

      executions = Map.new(attempts, &{&1.execution_id, {&1.step_id, &1.number}})

      {:ok, result, %{run_id: run_id, executions: executions}}
    end
  end

  def handle_insert(%Models.Run{} = run, value, state) do
    if run.execution_id do
      case Map.get(state.executions, run.execution_id) do
        nil ->
          {:ok, [], state}

        {step_id, attempt} ->
          run_ids = value.steps[step_id].attempts[attempt].run_ids

          if run.id not in run_ids do
            {:ok, [{[:steps, step_id, :attempts, attempt, :run_ids], [run.id | run_ids]}], state}
          end
      end
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.Step{} = step, _value, state) do
    if step.run_id == state.run_id do
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
        |> Map.put(:arguments, Enum.map(step.arguments, &compose_argument/1))
        |> Map.put(:attempts, %{})

      {:ok, [{[:steps, step.id], value}], state}
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.Attempt{} = attempt, _value, state) do
    if attempt.run_id == state.run_id do
      value =
        attempt
        |> Map.take([:created_at, :number, :execution_id])
        |> Map.put(:dependency_ids, [])
        |> Map.put(:run_ids, [])
        |> Map.put(:assigned_at, nil)
        |> Map.put(:result, nil)

      state = put_in(state.executions[attempt.execution_id], {attempt.step_id, attempt.number})
      {:ok, [{[:steps, attempt.step_id, :attempts, attempt.number], value}], state}
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.Assignment{} = assignment, _value, state) do
    case Map.get(state.executions, assignment.execution_id) do
      nil ->
        {:ok, [], state}

      {step_id, attempt} ->
        {:ok, [{[:steps, step_id, :attempts, attempt, :assigned_at], assignment.created_at}],
         state}
    end
  end

  def handle_insert(%Models.Result{} = result, _value, state) do
    case Map.get(state.executions, result.execution_id) do
      nil ->
        {:ok, [], state}

      {step_id, attempt} ->
        value = Map.take(result, [:type, :value, :created_at])
        {:ok, [{[:steps, step_id, :attempts, attempt, :result], value}], state}
    end
  end

  def handle_insert(%Models.Dependency{} = dependency, value, state) do
    case Map.get(state.executions, dependency.execution_id) do
      nil ->
        {:ok, [], state}

      {step_id, attempt} ->
        dependency_ids = value.steps[step_id].attempts[attempt].dependency_ids

        if dependency.dependency_id not in dependency_ids do
          {:ok,
           [
             {[:steps, step_id, :attempts, attempt, :dependency_ids],
              [dependency.dependency_id | dependency_ids]}
           ], state}
        else
          {:ok, [], state}
        end
    end
  end

  defp compose_argument(argument) do
    case argument do
      {:json, json} -> "json:#{json}"
      {:result, execution_id} -> "result:#{execution_id}"
      {:blob, hash} -> "blob:#{hash}"
    end
  end
end

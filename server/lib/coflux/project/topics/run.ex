defmodule Coflux.Project.Topics.Run do
  use Topical.Topic, route: "projects/:project_id/runs/:run_id"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener
  alias Coflux.Project

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    run_id = Keyword.fetch!(params, :run_id)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [
          Models.Run,
          Models.Step,
          Models.Attempt,
          Models.Assignment,
          Models.Result,
          Models.Dependency
        ]
      )

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

      results =
        Map.new(results, fn result ->
          {result.execution_id,
           result
           |> Map.take([:type, :value])
           |> Map.put(:createdAt, result.created_at)}
        end)

      execution_runs =
        execution_runs
        |> Enum.group_by(& &1.execution_id)
        |> Map.new(fn {execution_id, runs} ->
          # TODO: include run details (repository/target; from task or step?)
          {execution_id, Enum.map(runs, & &1.id)}
        end)

      result =
        run
        |> Map.take([:id])
        |> Map.put(:createdAt, run.created_at)
        |> Map.put(:environment, Map.take(environment, [:id, :name]))
        |> Map.put(
          :steps,
          Map.new(steps, fn step ->
            parent =
              if step.parent_step_id,
                do: %{stepId: step.parent_step_id, attempt: step.parent_attempt}

            cached =
              if step.cached_step_id,
                do: %{runId: step.cached_run_id, stepId: step.cached_step_id}

            value =
              step
              |> Map.take([:repository, :target])
              |> Map.put(:createdAt, step.created_at)
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
                    |> Map.take([:number])
                    |> Map.put(:createdAt, attempt.created_at)
                    |> Map.put(:executionId, attempt.execution_id)
                    |> Map.put(:dependencyIds, Map.get(dependencies, execution_id, []))
                    |> Map.put(:runIds, Map.get(execution_runs, execution_id, []))
                    |> Map.put(:assignedAt, Map.get(assigned_at, execution_id))
                    |> Map.put(:result, Map.get(results, execution_id))

                  {Integer.to_string(attempt.number), value}
                end)
              )

            {step.id, value}
          end)
        )

      executions = Map.new(attempts, &{&1.execution_id, {&1.step_id, &1.number}})
      topic = Topic.new(result, %{project_id: project_id, run_id: run_id, executions: executions})

      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Run{} = run}, topic) do
    if run.execution_id do
      case Map.get(topic.state.executions, run.execution_id) do
        nil ->
          {:ok, topic}

        {step_id, attempt} ->
          attempt_s = Integer.to_string(attempt)
          run_ids = topic.value.steps[step_id].attempts[attempt_s].runIds

          if run.id not in run_ids do
            topic =
              Topic.set(topic, [:steps, step_id, :attempts, attempt_s, :runIds], [run.id | run_ids])

            {:ok, topic}
          end
      end
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Step{} = step}, topic) do
    if step.run_id == topic.state.run_id do
      parent =
        if step.parent_step_id,
          do: %{stepId: step.parent_step_id, attempt: step.parent_attempt}

      cached =
        if step.cached_step_id,
          do: %{runId: step.cached_run_id, stepId: step.cached_step_id}

      value =
        step
        |> Map.take([:repository, :target])
        |> Map.put(:createdAt, step.created_at)
        |> Map.put(:id, step.id)
        |> Map.put(:parent, parent)
        |> Map.put(:cached, cached)
        |> Map.put(:arguments, Enum.map(step.arguments, &compose_argument/1))
        |> Map.put(:attempts, %{})

      topic = Topic.set(topic, [:steps, step.id], value)
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Attempt{} = attempt}, topic) do
    if attempt.run_id == topic.state.run_id do
      topic =
        put_in(topic.state.executions[attempt.execution_id], {attempt.step_id, attempt.number})

      topic =
        Topic.set(
          topic,
          [:steps, attempt.step_id, :attempts, Integer.to_string(attempt.number)],
          %{
            createdAt: attempt.created_at,
            number: attempt.number,
            executionId: attempt.execution_id,
            dependencyIds: [],
            runIds: [],
            assignedAt: nil,
            result: nil
          }
        )

      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Assignment{} = assignment}, topic) do
    case Map.get(topic.state.executions, assignment.execution_id) do
      nil ->
        {:ok, topic}

      {step_id, attempt} ->
        topic =
          Topic.set(
            topic,
            [:steps, step_id, :attempts, Integer.to_string(attempt), :assignedAt],
            assignment.created_at
          )

        {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Result{} = result}, topic) do
    case Map.get(topic.state.executions, result.execution_id) do
      nil ->
        {:ok, topic}

      {step_id, attempt} ->
        value =
          result
          |> Map.take([:type, :value])
          |> Map.put(:createdAt, result.created_at)

        topic = Topic.set(topic, [:steps, step_id, :attempts, Integer.to_string(attempt), :result], value)
        {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Dependency{} = dependency}, topic) do
    case Map.get(topic.state.executions, dependency.execution_id) do
      nil ->
        {:ok, topic}

      {step_id, attempt} ->
        attempt_s = Integer.to_string(attempt)
        dependency_ids = topic.value.steps[step_id].attempts[attempt_s].dependencyIds

        if dependency.dependency_id not in dependency_ids do
          topic =
            Topic.set(topic, [:steps, step_id, :attempts, attempt_s, :dependencyIds], [
              dependency.dependency_id | dependency_ids
            ])

          {:ok, topic}
        else
          {:ok, topic}
        end
    end
  end

  def handle_execute("rerun_step", {step_id, environment_name}, topic, _context) do
    with {:ok, environment} <-
           Project.get_environment_by_name(topic.state.project_id, environment_name) do
      case Project.rerun_step(topic.state.project_id, topic.state.run_id, step_id,
             environment_id: environment.id
           ) do
        {:ok, attempt} ->
          {:ok, attempt, topic}
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

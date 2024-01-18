defmodule Coflux.Topics.Run do
  use Topical.Topic,
    route: ["projects", :project_id, "environments", :environment_name, "runs", :run_id]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    external_run_id = Keyword.fetch!(params, :run_id)

    case Orchestration.subscribe_run(
           project_id,
           environment_name,
           external_run_id,
           self()
         ) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, run, parent, steps, _ref} ->
        {:ok,
         Topic.new(build_run(run, parent, steps), %{
           project_id: project_id,
           environment_name: environment_name,
           external_run_id: external_run_id
         })}
    end
  end

  def handle_info(
        {:topic, _ref, {:step, step_id, repository, target, created_at, arguments}},
        topic
      ) do
    topic =
      Topic.set(topic, [:steps, step_id], %{
        repository: repository,
        target: target,
        type: 1,
        createdAt: created_at,
        arguments: Enum.map(arguments, &build_argument/1),
        attempts: %{}
      })

    {:ok, topic}
  end

  def handle_info(
        {:topic, _ref,
         {:attempt, step_id, sequence, execution_type, execution_id, created_at, execute_after}},
        topic
      ) do
    topic =
      Topic.set(
        topic,
        [:steps, step_id, :attempts, Integer.to_string(sequence)],
        %{
          type: execution_type,
          executionId: Integer.to_string(execution_id),
          createdAt: created_at,
          executeAfter: execute_after,
          assignedAt: nil,
          completedAt: nil,
          dependencies: %{},
          children: [],
          result: nil,
          retry: nil
        }
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:assigned, assigned}}, topic) do
    topic =
      Enum.reduce(assigned, topic, fn {execution_id, assigned_at}, topic ->
        update_attempt(topic, execution_id, fn topic, base_path ->
          Topic.set(topic, base_path ++ [:assignedAt], assigned_at)
        end)
      end)

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:dependency, execution_id, dependency_id, dependency}}, topic) do
    dependency = build_execution(dependency)

    topic =
      update_attempt(
        topic,
        execution_id,
        fn topic, base_path ->
          Topic.set(
            topic,
            base_path ++ [:dependencies, Integer.to_string(dependency_id)],
            dependency
          )
        end
      )

    {:ok, topic}
  end

  def handle_info(
        {:topic, _ref,
         {:child, parent_id, external_run_id, external_step_id, execution_id, repository, target,
          created_at}},
        topic
      ) do
    value =
      if external_run_id == topic.state.external_run_id do
        external_step_id
      else
        %{
          runId: external_run_id,
          stepId: external_step_id,
          executionId: execution_id,
          repository: repository,
          target: target,
          createdAt: created_at
        }
      end

    topic =
      update_attempt(topic, parent_id, fn topic, base_path ->
        Topic.insert(topic, base_path ++ [:children], value)
      end)

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:result, execution_id, result, retry, created_at}}, topic) do
    result = build_result(result)
    retry = if(retry, do: build_execution(retry))

    topic =
      update_attempt(topic, execution_id, fn topic, base_path ->
        topic
        |> Topic.set(base_path ++ [:result], result)
        |> Topic.set(base_path ++ [:completedAt], created_at)
        |> Topic.set(base_path ++ [:retry], retry)
      end)

    {:ok, topic}
  end

  defp build_execution(execution) do
    %{
      runId: execution.run_id,
      stepId: execution.step_id,
      sequence: execution.sequence,
      repository: execution.repository,
      target: execution.target
    }
  end

  defp build_run(run, parent, steps) do
    %{
      createdAt: run.created_at,
      recurrent: run.recurrent,
      parent: if(parent, do: build_execution(parent)),
      steps:
        Map.new(steps, fn {step_id, step} ->
          {step_id,
           %{
             repository: step.repository,
             target: step.target,
             type: step.type,
             createdAt: step.created_at,
             arguments: Enum.map(step.arguments, &build_argument/1),
             attempts:
               Map.new(step.attempts, fn {sequence, execution} ->
                 {Integer.to_string(sequence),
                  %{
                    type: execution.type,
                    executionId: Integer.to_string(execution.execution_id),
                    createdAt: execution.created_at,
                    executeAfter: execution.execute_after,
                    assignedAt: execution.assigned_at,
                    completedAt: execution.completed_at,
                    dependencies:
                      Map.new(execution.dependencies, fn {dependency_id, dependency} ->
                        {Integer.to_string(dependency_id), build_execution(dependency)}
                      end),
                    children:
                      Enum.map(
                        execution.children,
                        fn {external_run_id, external_step_id, execution_id, repository, target,
                            created_at} ->
                          if external_run_id == run.external_id do
                            external_step_id
                          else
                            %{
                              runId: external_run_id,
                              stepId: external_step_id,
                              executionId: Integer.to_string(execution_id),
                              repository: repository,
                              target: target,
                              createdAt: created_at
                            }
                          end
                        end
                      ),
                    result: build_result(execution.result),
                    retry: if(execution.retry, do: build_execution(execution.retry))
                  }}
               end)
           }}
        end)
    }
  end

  defp build_argument(argument) do
    case argument do
      {:reference, execution_id} ->
        %{type: "reference", executionId: execution_id}

      {:raw, format, value} ->
        %{type: "raw", format: format, value: value}

      {:blob, format, key} ->
        %{type: "blob", format: format, key: key}
    end
  end

  defp build_result(result) do
    case result do
      {:error, error, _details} ->
        %{type: "error", error: error}

      {:reference, execution_id} ->
        %{type: "reference", executionId: execution_id}

      {:raw, format, value} ->
        %{type: "raw", format: format, value: value}

      {:blob, format, key} ->
        %{type: "blob", format: format, key: key}

      :abandoned ->
        %{type: "abandoned"}

      :cancelled ->
        %{type: "cancelled"}

      :duplicated ->
        %{type: "duplicated"}

      nil ->
        nil
    end
  end

  def update_attempt(topic, execution_id, fun) do
    execution_id_s = Integer.to_string(execution_id)

    Enum.reduce(topic.value.steps, topic, fn {step_id, step}, topic ->
      Enum.reduce(step.attempts, topic, fn {sequence, attempt}, topic ->
        if attempt.executionId == execution_id_s do
          fun.(topic, [:steps, step_id, :attempts, sequence])
        else
          topic
        end
      end)
    end)
  end
end

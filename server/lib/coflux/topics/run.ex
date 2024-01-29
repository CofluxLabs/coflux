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

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(
         topic,
         {:step, step_id, repository, target, memo_key, created_at, arguments}
       ) do
    Topic.set(topic, [:steps, step_id], %{
      repository: repository,
      target: target,
      isInitial: false,
      isMemoised: !is_nil(memo_key),
      createdAt: created_at,
      arguments: Enum.map(arguments, &build_value/1),
      attempts: %{}
    })
  end

  defp process_notification(
         topic,
         {:attempt, step_id, sequence, execution_type, execution_id, created_at, execute_after}
       ) do
    Topic.set(
      topic,
      [:steps, step_id, :attempts, Integer.to_string(sequence)],
      %{
        isCached: execution_type == 1,
        executionId: Integer.to_string(execution_id),
        createdAt: created_at,
        executeAfter: execute_after,
        assignedAt: nil,
        completedAt: nil,
        dependencies: %{},
        children: [],
        result: nil,
        reference: nil
      }
    )
  end

  defp process_notification(topic, {:assigned, assigned}) do
    Enum.reduce(assigned, topic, fn {execution_id, assigned_at}, topic ->
      update_attempt(topic, execution_id, fn topic, base_path ->
        Topic.set(topic, base_path ++ [:assignedAt], assigned_at)
      end)
    end)
  end

  defp process_notification(topic, {:dependency, execution_id, dependency_id, dependency}) do
    dependency = build_execution(dependency)

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
  end

  defp process_notification(topic, {:child, parent_id, child}) do
    value = build_child(child, topic.state.external_run_id)

    update_attempt(topic, parent_id, fn topic, base_path ->
      Topic.insert(topic, base_path ++ [:children], value)
    end)
  end

  defp process_notification(topic, {:result, execution_id, result, created_at}) do
    result = build_result(result)

    update_attempt(topic, execution_id, fn topic, base_path ->
      topic
      |> Topic.set(base_path ++ [:result], result)
      |> Topic.set(base_path ++ [:completedAt], created_at)
    end)
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
             isInitial: step.type == 0,
             isMemoised: !is_nil(step.memo_key),
             createdAt: step.created_at,
             arguments: Enum.map(step.arguments, &build_value/1),
             attempts:
               Map.new(step.attempts, fn {sequence, execution} ->
                 {Integer.to_string(sequence),
                  %{
                    isCached: execution.type == 1,
                    executionId: Integer.to_string(execution.execution_id),
                    createdAt: execution.created_at,
                    executeAfter: execution.execute_after,
                    assignedAt: execution.assigned_at,
                    completedAt: execution.completed_at,
                    dependencies:
                      Map.new(execution.dependencies, fn {dependency_id, dependency} ->
                        {Integer.to_string(dependency_id), build_execution(dependency)}
                      end),
                    children: Enum.map(execution.children, &build_child(&1, run.external_id)),
                    result: build_result(execution.result)
                  }}
               end)
           }}
        end)
    }
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

  defp build_value(value) do
    case value do
      {:raw, format, content, references, metadata} ->
        %{
          type: "raw",
          format: format,
          content: content,
          references: build_references(references),
          metadata: metadata
        }

      {:blob, format, key, references, metadata} ->
        %{
          type: "blob",
          format: format,
          key: key,
          references: build_references(references),
          metadata: metadata
        }
    end
  end

  defp build_references(references) do
    Map.new(references, fn {placeholder, {execution_id, execution}} ->
      {placeholder, [execution_id, build_execution(execution)]}
    end)
  end

  defp build_result(result) do
    case result do
      {:error, error, _details, retry_id} ->
        %{type: "error", error: error, retryId: retry_id}

      {:value, value} ->
        %{type: "value", value: build_value(value)}

      {:abandoned, retry_id} ->
        %{type: "abandoned", retryId: retry_id}

      :cancelled ->
        %{type: "cancelled"}

      {:deferred, execution_id, execution} ->
        %{type: "deferred", executionId: execution_id, execution: build_execution(execution)}

      nil ->
        nil
    end
  end

  defp build_child(
         {external_run_id, external_step_id, execution_id, repository, target, created_at},
         run_external_id
       ) do
    if external_run_id == run_external_id do
      external_step_id
    else
      %{
        runId: external_run_id,
        stepId: external_step_id,
        executionId: if(execution_id, do: Integer.to_string(execution_id)),
        repository: repository,
        target: target,
        createdAt: created_at
      }
    end
  end

  defp update_attempt(topic, execution_id, fun) do
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

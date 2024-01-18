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
        {:topic, _ref,
         {:step, step_id, repository, target, created_at, arguments, cached_execution_id}},
        topic
      ) do
    topic =
      Topic.set(topic, [:steps, step_id], %{
        repository: repository,
        target: target,
        type: 1,
        createdAt: created_at,
        cachedExecutionId: if(cached_execution_id, do: Integer.to_string(cached_execution_id)),
        arguments: Enum.map(arguments, &build_argument/1),
        executions: %{}
      })

    {:ok, topic}
  end

  def handle_info(
        {:topic, _ref, {:execution, execution_id, step_id, sequence, created_at, execute_after}},
        topic
      ) do
    topic =
      Topic.set(
        topic,
        [:steps, step_id, :executions, Integer.to_string(execution_id)],
        %{
          sequence: sequence,
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
        step_id = find_step_id_for_execution(topic, execution_id)

        Topic.set(
          topic,
          [
            :steps,
            step_id,
            :executions,
            Integer.to_string(execution_id),
            :assignedAt
          ],
          assigned_at
        )
      end)

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:dependency, execution_id, dependency_id, dependency}}, topic) do
    step_id = find_step_id_for_execution(topic, execution_id)

    topic =
      Topic.set(
        topic,
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :dependencies,
          Integer.to_string(dependency_id)
        ],
        build_execution(dependency)
      )

    {:ok, topic}
  end

  def handle_info(
        {:topic, _ref,
         {:child, parent_id, external_run_id, external_step_id, execution_id, repository, target,
          created_at}},
        topic
      ) do
    parent_step_id = find_step_id_for_execution(topic, parent_id)

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
      Topic.insert(
        topic,
        [
          :steps,
          parent_step_id,
          :executions,
          Integer.to_string(parent_id),
          :children
        ],
        value
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:result, execution_id, result, retry, created_at}}, topic) do
    step_id = find_step_id_for_execution(topic, execution_id)

    topic =
      topic
      |> Topic.set(
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :result
        ],
        build_result(result)
      )
      |> Topic.set(
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :completedAt
        ],
        created_at
      )
      |> Topic.set(
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :retry
        ],
        if(retry, do: build_execution(retry))
      )

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
             cachedExecutionId:
               if(step.cached_execution_id, do: Integer.to_string(step.cached_execution_id)),
             arguments: Enum.map(step.arguments, &build_argument/1),
             executions:
               Map.new(step.executions, fn {execution_id, execution} ->
                 {
                   Integer.to_string(execution_id),
                   %{
                     sequence: execution.sequence,
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
                               executionId: execution_id,
                               repository: repository,
                               target: target,
                               createdAt: created_at
                             }
                           end
                         end
                       ),
                     result: build_result(execution.result),
                     retry: if(execution.retry, do: build_execution(execution.retry))
                   }
                 }
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

  defp find_step_id_for_execution(topic, execution_id) do
    execution_id_s = Integer.to_string(execution_id)

    case Enum.find(topic.value.steps, fn {_, step} ->
           Map.has_key?(step.executions, execution_id_s)
         end) do
      {step_id, _} -> step_id
    end
  end
end

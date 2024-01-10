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
         {:step, step_id, parent_id, repository, target, created_at, arguments,
          cached_execution_id}},
        topic
      ) do
    topic =
      Topic.set(topic, [:steps, step_id], %{
        repository: repository,
        target: target,
        parentId: if(parent_id, do: Integer.to_string(parent_id)),
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
          dependencies: [],
          children: %{},
          result: nil,
          retry: nil
        }
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:assignment, execution_id, created_at}}, topic) do
    step_id = find_step_id_for_execution(topic, execution_id)

    topic =
      Topic.set(
        topic,
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :assignedAt
        ],
        created_at
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:dependency, execution_id, dependency_id}}, topic) do
    step_id = find_step_id_for_execution(topic, execution_id)

    topic =
      Topic.insert(
        topic,
        [
          :steps,
          step_id,
          :executions,
          Integer.to_string(execution_id),
          :dependencies
        ],
        Integer.to_string(dependency_id)
      )

    {:ok, topic}
  end

  def handle_info(
        {:topic, _ref,
         {:child, parent_id, external_run_id, created_at, repository, target, execution_id}},
        topic
      ) do
    step_id = find_step_id_for_execution(topic, parent_id)

    topic =
      Topic.set(
        topic,
        [:steps, step_id, :executions, Integer.to_string(parent_id), :children, external_run_id],
        %{
          createdAt: created_at,
          repository: repository,
          target: target,
          executionId: if(execution_id, do: Integer.to_string(execution_id))
        }
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
        # TODO
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
        build_retry(retry)
      )

    {:ok, topic}
  end

  def handle_execute("cancel_run", {}, topic, _context) do
    case Orchestration.cancel_run(
           topic.state.project_id,
           topic.state.environment_name,
           topic.state.external_run_id
         ) do
      :ok ->
        {:ok, true, topic}
    end
  end

  def handle_execute("rerun_step", {step_id}, topic, _context) do
    case Orchestration.rerun_step(
           topic.state.project_id,
           topic.state.environment_name,
           step_id
         ) do
      {:ok, _execution_id, sequence} ->
        {:ok, sequence, topic}
    end
  end

  defp build_run(run, parent, steps) do
    parent =
      case parent do
        {run_external_id, step_external_id, sequence, repository, target} ->
          %{
            runId: run_external_id,
            stepId: step_external_id,
            sequence: sequence,
            repository: repository,
            target: target
          }

        nil ->
          nil
      end

    %{
      createdAt: run.created_at,
      recurrent: run.recurrent,
      parent: parent,
      steps:
        Map.new(steps, fn {step_id, step} ->
          {step_id,
           %{
             repository: step.repository,
             target: step.target,
             parentId: if(step.parent_id, do: Integer.to_string(step.parent_id)),
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
                     dependencies: Enum.map(execution.dependencies, &Integer.to_string/1),
                     children:
                       Map.new(
                         execution.children,
                         fn {external_run_id, created_at, repository, target, execution_id} ->
                           {external_run_id,
                            %{
                              createdAt: created_at,
                              repository: repository,
                              target: target,
                              executionId: if(execution_id, do: Integer.to_string(execution_id))
                            }}
                         end
                       ),
                     result: build_result(execution.result),
                     retry: build_retry(execution.retry)
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

  defp build_retry(retry) do
    if retry do
      %{
        runId: retry.run_id,
        stepId: retry.step_id,
        sequence: retry.sequence
      }
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

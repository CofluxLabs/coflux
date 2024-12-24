defmodule Coflux.Topics.Run do
  use Topical.Topic, route: ["projects", :project_id, "runs", :run_id, :environment_id]

  alias Coflux.Orchestration

  import Coflux.TopicUtils

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    external_run_id = Keyword.fetch!(params, :run_id)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))

    case Orchestration.subscribe_run(
           project_id,
           external_run_id,
           self()
         ) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, run, parent, steps, _ref} ->
        run_environment_id =
          steps
          |> Map.values()
          |> Enum.reject(& &1.parent_id)
          |> Enum.min_by(& &1.created_at)
          |> Map.fetch!(:executions)
          |> Map.values()
          |> Enum.min_by(& &1.created_at)
          |> Map.fetch!(:environment_id)

        environment_ids = Enum.uniq([run_environment_id, environment_id])

        {:ok,
         Topic.new(build_run(run, parent, steps, environment_ids), %{
           project_id: project_id,
           external_run_id: external_run_id,
           environment_ids: environment_ids
         })}
    end
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(
         topic,
         {:step, step_id, repository, target, type, is_memoised, parent_id, created_at, arguments,
          requires, attempt, execution_id, environment_id, execute_after}
       ) do
    if environment_id in topic.state.environment_ids do
      Topic.set(topic, [:steps, step_id], %{
        repository: repository,
        target: target,
        type: type,
        parentId: if(parent_id, do: Integer.to_string(parent_id)),
        isMemoised: is_memoised,
        createdAt: created_at,
        arguments: Enum.map(arguments, &build_value/1),
        requires: requires,
        executions: %{
          Integer.to_string(attempt) => %{
            executionId: Integer.to_string(execution_id),
            environmentId: Integer.to_string(environment_id),
            createdAt: created_at,
            executeAfter: execute_after,
            assignedAt: nil,
            completedAt: nil,
            assets: %{},
            dependencies: %{},
            children: [],
            result: nil,
            logCount: 0
          }
        }
      })
    else
      topic
    end
  end

  defp process_notification(
         topic,
         {:execution, step_id, attempt, execution_id, environment_id, created_at, execute_after}
       ) do
    if environment_id in topic.state.environment_ids do
      Topic.set(
        topic,
        [:steps, step_id, :executions, Integer.to_string(attempt)],
        %{
          executionId: Integer.to_string(execution_id),
          environmentId: Integer.to_string(environment_id),
          createdAt: created_at,
          executeAfter: execute_after,
          assignedAt: nil,
          completedAt: nil,
          assets: %{},
          dependencies: %{},
          children: [],
          result: nil,
          logCount: 0
        }
      )
    else
      topic
    end
  end

  defp process_notification(topic, {:asset, execution_id, asset_id, asset}) do
    asset = build_asset(asset)

    update_execution(
      topic,
      execution_id,
      fn topic, base_path ->
        Topic.set(
          topic,
          base_path ++ [:assets, Integer.to_string(asset_id)],
          asset
        )
      end
    )
  end

  defp process_notification(topic, {:assigned, assigned}) do
    Enum.reduce(assigned, topic, fn {execution_id, assigned_at}, topic ->
      update_execution(topic, execution_id, fn topic, base_path ->
        Topic.set(topic, base_path ++ [:assignedAt], assigned_at)
      end)
    end)
  end

  defp process_notification(topic, {:result_dependency, execution_id, dependency_id, dependency}) do
    dependency = build_dependency(dependency)

    update_execution(
      topic,
      execution_id,
      fn topic, base_path ->
        Topic.merge(
          topic,
          base_path ++ [:dependencies, Integer.to_string(dependency_id)],
          dependency
        )
      end
    )
  end

  defp process_notification(topic, {:child, parent_id, child}) do
    value = build_child(child, topic.state.external_run_id)

    update_execution(topic, parent_id, fn topic, base_path ->
      Topic.insert(topic, base_path ++ [:children], value)
    end)
  end

  defp process_notification(topic, {:result, execution_id, result, created_at}) do
    result = build_result(result)

    update_execution(topic, execution_id, fn topic, base_path ->
      topic
      |> Topic.set(base_path ++ [:result], result)
      |> Topic.set(base_path ++ [:completedAt], created_at)
    end)
  end

  defp process_notification(topic, {:result_result, execution_id, result, _created_at}) do
    result = build_result(result)

    update_execution(topic, execution_id, fn topic, base_path ->
      Topic.set(topic, base_path ++ [:result, :result], result)
    end)
  end

  defp process_notification(topic, {:log_counts, execution_id, delta}) do
    update_execution(topic, execution_id, fn topic, base_path ->
      path = base_path ++ [:logCount]
      count = get_in(topic.value, path) + delta
      Topic.set(topic, base_path ++ [:logCount], count)
    end)
  end

  defp build_run(run, parent, steps, environment_ids) do
    %{
      createdAt: run.created_at,
      parent: if(parent, do: build_execution(parent)),
      steps:
        steps
        |> Enum.filter(fn {_, step} ->
          step.executions
          |> Map.values()
          |> Enum.any?(&(&1.environment_id in environment_ids))
        end)
        |> Map.new(fn {step_id, step} ->
          {step_id,
           %{
             repository: step.repository,
             target: step.target,
             type: step.type,
             parentId: if(step.parent_id, do: Integer.to_string(step.parent_id)),
             isMemoised: !is_nil(step.memo_key),
             createdAt: step.created_at,
             arguments: Enum.map(step.arguments, &build_value/1),
             requires: step.requires,
             executions:
               step.executions
               |> Enum.filter(fn {_, execution} ->
                 execution.environment_id in environment_ids
               end)
               |> Map.new(fn {attempt, execution} ->
                 {Integer.to_string(attempt),
                  %{
                    executionId: Integer.to_string(execution.execution_id),
                    environmentId: Integer.to_string(execution.environment_id),
                    createdAt: execution.created_at,
                    executeAfter: execution.execute_after,
                    assignedAt: execution.assigned_at,
                    completedAt: execution.completed_at,
                    assets:
                      Map.new(execution.assets, fn {asset_id, asset} ->
                        {Integer.to_string(asset_id), build_asset(asset)}
                      end),
                    dependencies: build_dependencies(execution.dependencies),
                    children: Enum.map(execution.children, &build_child(&1, run.external_id)),
                    result: build_result(execution.result),
                    logCount: execution.log_count
                  }}
               end)
           }}
        end)
    }
  end

  defp build_dependencies(dependencies) do
    Map.new(dependencies, fn {execution_id, execution} ->
      {execution_id, build_dependency(execution)}
    end)
  end

  defp build_dependency(execution) do
    %{
      execution: build_execution(execution)
    }
  end

  defp build_frames(frames) do
    Enum.map(frames, fn {file, line, name, code} ->
      %{
        file: file,
        line: line,
        name: name,
        code: code
      }
    end)
  end

  defp build_result(result) do
    case result do
      {:error, type, message, frames, retry} ->
        %{
          type: "error",
          error: %{
            type: type,
            message: message,
            frames: build_frames(frames)
          },
          retry: if(retry, do: retry.attempt)
        }

      {:value, value} ->
        %{type: "value", value: build_value(value)}

      {:abandoned, retry} ->
        %{type: "abandoned", retry: if(retry, do: retry.attempt)}

      :cancelled ->
        %{type: "cancelled"}

      {:suspended, successor} ->
        %{type: "suspended", successor: if(successor, do: successor.attempt)}

      {:deferred, execution, result} ->
        %{type: "deferred", execution: build_execution(execution), result: build_result(result)}

      {:cached, execution, result} ->
        %{type: "cached", execution: build_execution(execution), result: build_result(result)}

      {:spawned, execution, result} ->
        %{type: "spawned", execution: build_execution(execution), result: build_result(result)}

      nil ->
        nil
    end
  end

  defp build_child({external_run_id, external_step_id, repository, target, type}, run_external_id) do
    if external_run_id == run_external_id do
      external_step_id
    else
      %{
        runId: external_run_id,
        stepId: external_step_id,
        repository: repository,
        target: target,
        type: type
      }
    end
  end

  defp update_execution(topic, execution_id, fun) do
    execution_id_s = Integer.to_string(execution_id)

    Enum.reduce(topic.value.steps, topic, fn {step_id, step}, topic ->
      Enum.reduce(step.executions, topic, fn {attempt, execution}, topic ->
        if execution.executionId == execution_id_s do
          fun.(topic, [:steps, step_id, :executions, attempt])
        else
          topic
        end
      end)
    end)
  end
end

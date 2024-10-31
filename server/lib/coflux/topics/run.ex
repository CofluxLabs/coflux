defmodule Coflux.Topics.Run do
  use Topical.Topic, route: ["projects", :project_id, "runs", :run_id, :environment_id]

  alias Coflux.Orchestration

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
         {:step, step_id, repository, target, is_memoised, parent_id, created_at, arguments,
          requires, attempt, execution_id, environment_id, execute_after}
       ) do
    if environment_id in topic.state.environment_ids do
      Topic.set(topic, [:steps, step_id], %{
        repository: repository,
        target: target,
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
            reference: nil
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
          reference: nil
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

  defp process_notification(
         topic,
         {:asset_dependency, execution_id, asset_execution_id, asset_execution, asset_id, asset}
       ) do
    asset = build_asset(asset)
    asset_execution = build_dependency(asset_execution)

    asset_execution_id_s = Integer.to_string(asset_execution_id)
    asset_id_s = Integer.to_string(asset_id)

    update_execution(
      topic,
      execution_id,
      fn topic, base_path ->
        topic
        |> Topic.merge(base_path ++ [:dependencies, asset_execution_id_s], asset_execution)
        |> Topic.set(
          base_path ++ [:dependencies, asset_execution_id_s, :assets, asset_id_s],
          asset
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

  defp build_run(run, parent, steps, environment_ids) do
    %{
      createdAt: run.created_at,
      recurrent: run.recurrent,
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
                    dependencies:
                      build_dependencies(
                        execution.result_dependencies,
                        execution.asset_dependencies
                      ),
                    children: Enum.map(execution.children, &build_child(&1, run.external_id)),
                    result: build_result(execution.result)
                  }}
               end)
           }}
        end)
    }
  end

  defp build_dependencies(result_dependencies, asset_dependencies) do
    dependencies =
      Map.new(result_dependencies, fn {execution_id, execution} ->
        {execution_id, build_dependency(execution)}
      end)

    Enum.reduce(asset_dependencies, dependencies, fn {asset_id, asset}, dependencies ->
      dependencies
      |> Map.put_new_lazy(asset.execution_id, fn ->
        build_dependency(asset.execution)
      end)
      |> Map.update!(asset.execution_id, fn dependency ->
        put_in(dependency.assets[asset_id], build_asset(asset))
      end)
    end)
  end

  defp build_execution(execution) do
    %{
      runId: execution.run_id,
      stepId: execution.step_id,
      attempt: execution.attempt,
      repository: execution.repository,
      target: execution.target
    }
  end

  defp build_dependency(execution) do
    execution
    |> build_execution()
    |> Map.put(:assets, %{})
  end

  defp build_asset(asset) do
    %{
      type: asset.type,
      path: asset.path,
      metadata: asset.metadata,
      blobKey: asset.blob_key,
      size: asset.size,
      createdAt: asset.created_at
    }
  end

  defp build_value(value) do
    case value do
      {:raw, data, references} ->
        %{
          type: "raw",
          data: data,
          references: build_references(references)
        }

      {:blob, key, size, references} ->
        %{
          type: "blob",
          key: key,
          size: size,
          references: build_references(references)
        }
    end
  end

  defp build_references(references) do
    Enum.map(references, fn
      {:block, serialiser, blob_key, size, metadata} ->
        %{
          type: "block",
          serialiser: serialiser,
          blobKey: blob_key,
          size: size,
          metadata: metadata
        }

      {:execution, execution_id, execution} ->
        %{
          type: "execution",
          executionId: Integer.to_string(execution_id),
          execution: build_execution(execution)
        }

      {:asset, asset_id, asset} ->
        %{
          type: "asset",
          assetId: Integer.to_string(asset_id),
          asset: build_asset(asset)
        }
    end)
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
      {:error, type, message, frames, retry_id} ->
        %{
          type: "error",
          error: %{
            type: type,
            message: message,
            frames: build_frames(frames)
          },
          retryId: retry_id
        }

      {:value, value} ->
        %{type: "value", value: build_value(value)}

      {:abandoned, retry_id} ->
        %{type: "abandoned", retryId: retry_id}

      :cancelled ->
        %{type: "cancelled"}

      {:deferred, execution_id, execution} ->
        %{type: "deferred", executionId: execution_id, execution: build_execution(execution)}

      {:cached, execution_id, execution} ->
        %{type: "cached", executionId: execution_id, execution: build_execution(execution)}

      {:suspended, successor_id} ->
        %{type: "suspended", successorId: successor_id}

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

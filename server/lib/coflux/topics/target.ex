defmodule Coflux.Topics.Target do
  use Topical.Topic,
    route: [
      "projects",
      :project_id,
      "environments",
      :environment_name,
      "targets",
      :repository,
      :target
    ]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    repository = Keyword.fetch!(params, :repository)
    target_name = Keyword.fetch!(params, :target)

    case Orchestration.subscribe_target(
           project_id,
           environment_name,
           repository,
           target_name,
           self()
         ) do
      {:ok, target, runs, ref} ->
        runs =
          Map.new(runs, fn {external_run_id, created_at} ->
            {external_run_id, %{id: external_run_id, createdAt: created_at}}
          end)

        target = %{
          repository: repository,
          target: target_name,
          type: target.type,
          parameters: build_parameters(target.parameters),
          runs: runs
        }

        {:ok, Topic.new(target, %{ref: ref})}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def handle_info({:topic, _ref, {:target, type, parameters}}, topic) do
    topic =
      topic
      |> Topic.set([:type], type)
      |> Topic.set([:parameters], build_parameters(parameters))

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:run, external_run_id, created_at}}, topic) do
    topic =
      Topic.set(
        topic,
        [:runs, external_run_id],
        %{id: external_run_id, createdAt: created_at}
      )

    {:ok, topic}
  end

  defp build_parameters(parameters) do
    Enum.map(parameters, fn {name, default, annotation} ->
      %{name: name, default: default, annotation: annotation}
    end)
  end
end

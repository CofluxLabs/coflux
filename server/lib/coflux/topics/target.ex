defmodule Coflux.Topics.Target do
  use Topical.Topic,
    route: ["projects", :project_id, "targets", :repository, :target, :environment_id]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    repository = Keyword.fetch!(params, :repository)
    target_name = Keyword.fetch!(params, :target)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))

    case Orchestration.subscribe_target(
           project_id,
           repository,
           target_name,
           environment_id,
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
          type: if(target, do: target.type),
          parameters: if(target, do: build_parameters(target.parameters)),
          runs: runs
        }

        {:ok, Topic.new(target, %{ref: ref})}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification/2)
    {:ok, topic}
  end

  defp process_notification({:target, type, parameters}, topic) do
    topic
    |> Topic.set([:type], type)
    |> Topic.set([:parameters], build_parameters(parameters))
  end

  defp process_notification({:run, external_run_id, created_at}, topic) do
    Topic.set(
      topic,
      [:runs, external_run_id],
      %{id: external_run_id, createdAt: created_at}
    )
  end

  defp build_parameters(parameters) do
    Enum.map(parameters, fn {name, default, annotation} ->
      %{name: name, default: default, annotation: annotation}
    end)
  end
end

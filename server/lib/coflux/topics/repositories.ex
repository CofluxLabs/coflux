defmodule Coflux.Topics.Repositories do
  use Topical.Topic, route: "projects/:project_id/environments/:environment_name/repositories"

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    {:ok, repositories, ref} =
      Orchestration.subscribe_repositories(project_id, environment_name, self())

    repositories =
      Map.new(repositories, fn {repository, targets} ->
        {repository, targets |> filter_targets() |> Map.new(&build_target/1)}
      end)

    {:ok, Topic.new(repositories, %{ref: ref})}
  end

  def handle_info({:topic, _ref, {:targets, repository, targets}}, topic) do
    topic =
      Topic.set(topic, [repository], targets |> filter_targets() |> Map.new(&build_target/1))

    {:ok, topic}
  end

  defp filter_targets(targets) do
    Map.filter(targets, fn {_, target} ->
      target.type in [:task, :sensor]
    end)
  end

  defp build_target({name, target}) do
    {name,
     %{
       type: target.type,
       parameters:
         Enum.map(target.parameters, fn {name, default, annotation} ->
           %{name: name, default: default, annotation: annotation}
         end)
     }}
  end
end
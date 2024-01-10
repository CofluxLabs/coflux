defmodule Coflux.Topics.Repositories do
  use Topical.Topic,
    route: ["projects", :project_id, "environments", :environment_name, "repositories"]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    {:ok, targets, stats, ref} =
      Orchestration.subscribe_repositories(project_id, environment_name, self())

    repositories =
      targets
      |> Map.keys()
      |> Map.new(fn repository ->
        repository_targets =
          targets |> Map.fetch!(repository) |> filter_targets() |> Map.new(&build_target/1)

        repository_stats = stats |> Map.get(repository) |> build_stats()
        {repository, %{targets: repository_targets, stats: repository_stats}}
      end)

    {:ok, Topic.new(repositories, %{ref: ref})}
  end

  def handle_info({:topic, _ref, {:targets, repository, targets}}, topic) do
    topic =
      Topic.set(
        topic,
        [repository, :targets],
        targets |> filter_targets() |> Map.new(&build_target/1)
      )

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:stats, repository, stats}}, topic) do
    topic = Topic.set(topic, [repository, :stats], build_stats(stats))
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

  defp build_stats(stats) do
    if is_nil(stats) do
      %{executing: 0, nextDueAt: nil, scheduled: 0}
    else
      next_due_at =
        stats.scheduled
        |> Map.values()
        |> Enum.max(fn -> nil end)

      %{
        executing: Enum.count(stats.executing),
        nextDueAt: next_due_at,
        scheduled: Enum.count(stats.scheduled)
      }
    end
  end
end

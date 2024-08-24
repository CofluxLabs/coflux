defmodule Coflux.Topics.Repositories do
  use Topical.Topic, route: ["projects", :project_id, "repositories", :environment_name]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    {:ok, targets, executions, ref} =
      Orchestration.subscribe_repositories(project_id, environment_name, self())

    value =
      targets
      |> Map.keys()
      |> Map.new(fn repository ->
        repository_targets =
          targets |> Map.fetch!(repository) |> filter_targets() |> Map.new(&build_target/1)

        result = %{
          targets: repository_targets,
          executing: 0,
          scheduled: 0,
          nextDueAt: nil
        }

        result =
          case Map.fetch(executions, repository) do
            {:ok, {executing, scheduled}} ->
              next_due_at = scheduled |> Map.values() |> Enum.min(fn -> nil end)

              result
              |> Map.put(:executing, MapSet.size(executing))
              |> Map.put(:scheduled, map_size(scheduled))
              |> Map.put(:nextDueAt, next_due_at)

            :error ->
              result
          end

        {repository, result}
      end)

    {:ok, Topic.new(value, %{ref: ref, executions: executions})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:targets, repository, targets}) do
    targets = targets |> filter_targets() |> Map.new(&build_target/1)
    Topic.set(topic, [repository, :targets], targets)
  end

  defp process_notification(topic, {:scheduled, repository, execution_id, execute_at}) do
    update_executing(topic, repository, fn {executing, scheduled} ->
      scheduled = Map.put(scheduled, execution_id, execute_at)
      {executing, scheduled}
    end)
  end

  defp process_notification(topic, {:assigned, executions}) do
    Enum.reduce(executions, topic, fn {repository, execution_ids}, topic ->
      update_executing(topic, repository, fn {executing, scheduled} ->
        executing = MapSet.union(executing, execution_ids)
        scheduled = Map.drop(scheduled, MapSet.to_list(execution_ids))
        {executing, scheduled}
      end)
    end)
  end

  defp process_notification(topic, {:completed, repository, execution_id}) do
    update_executing(topic, repository, fn {executing, scheduled} ->
      executing = MapSet.delete(executing, execution_id)
      scheduled = Map.delete(scheduled, execution_id)
      {executing, scheduled}
    end)
  end

  defp filter_targets(targets) do
    Map.filter(targets, fn {_, target} ->
      target.type in [:workflow, :sensor]
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

  defp update_executing(topic, repository, fun) do
    default = {MapSet.new(), %{}}

    topic =
      update_in(
        topic,
        [Access.key(:state), :executions, Access.key(repository, default)],
        fun
      )

    {executing, scheduled} = topic.state.executions[repository]
    next_due_at = scheduled |> Map.values() |> Enum.min(fn -> nil end)

    topic
    |> Topic.set([repository, :executing], MapSet.size(executing))
    |> Topic.set([repository, :scheduled], map_size(scheduled))
    |> Topic.set([repository, :nextDueAt], next_due_at)
  end
end

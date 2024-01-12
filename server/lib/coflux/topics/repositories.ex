defmodule Coflux.Topics.Repositories do
  use Topical.Topic,
    route: ["projects", :project_id, "environments", :environment_name, "repositories"]

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
            {:ok, executions} ->
              next_due_at = executions.scheduled |> Map.values() |> Enum.min(fn -> nil end)

              result
              |> Map.put(:executing, MapSet.size(executions.executing))
              |> Map.put(:scheduled, map_size(executions.scheduled))
              |> Map.put(:nextDueAt, next_due_at)

            :error ->
              result
          end

        {repository, result}
      end)

    {:ok, Topic.new(value, %{ref: ref, executions: executions})}
  end

  def handle_info({:topic, _ref, {:targets, repository, targets}}, topic) do
    targets = targets |> filter_targets() |> Map.new(&build_target/1)
    topic = Topic.set(topic, [repository, :targets], targets)
    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:scheduled, repository, execution_id, execute_at}}, topic) do
    topic =
      update_executing(topic, repository, fn {executing, scheduled} ->
        scheduled = Map.put(scheduled, execution_id, execute_at)
        {executing, scheduled}
      end)

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:assigned, executions}}, topic) do
    topic =
      Enum.reduce(executions, topic, fn {repository, execution_ids}, topic ->
        update_executing(topic, repository, fn {executing, scheduled} ->
          executing = MapSet.union(executing, execution_ids)
          scheduled = Map.drop(scheduled, MapSet.to_list(execution_ids))
          {executing, scheduled}
        end)
      end)

    {:ok, topic}
  end

  def handle_info({:topic, _ref, {:completed, repository, execution_id}}, topic) do
    topic =
      update_executing(topic, repository, fn {executing, scheduled} ->
        executing = MapSet.delete(executing, execution_id)
        scheduled = Map.delete(scheduled, execution_id)
        {executing, scheduled}
      end)

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

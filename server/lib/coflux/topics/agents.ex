defmodule Coflux.Topics.Agents do
  use Topical.Topic, route: "projects/:project_id/environments/:environment_name/agents"

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    {:ok, agents, ref} = Orchestration.subscribe_agents(project_id, environment_name, self())

    agents =
      Map.new(agents, fn {session_id, targets} ->
        {session_id, build_targets(targets)}
      end)

    {:ok, Topic.new(agents, %{ref: ref})}
  end

  def handle_info({:topic, _ref, {:agent, session_id, targets}}, topic) do
    topic =
      if is_nil(targets) do
        Topic.unset(topic, [], Integer.to_string(session_id))
      else
        Topic.set(topic, [Integer.to_string(session_id)], build_targets(targets))
      end

    {:ok, topic}
  end

  defp build_targets(targets) do
    Map.new(targets, fn {repository, repository_targets} ->
      {repository, MapSet.to_list(repository_targets)}
    end)
  end
end
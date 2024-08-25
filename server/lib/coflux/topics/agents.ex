defmodule Coflux.Topics.Agents do
  use Topical.Topic, route: ["projects", :project_id, "agents", :environment_name]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    {:ok, agents, ref} = Orchestration.subscribe_agents(project_id, environment_name, self())

    agents =
      Map.new(agents, fn {session_id, targets} ->
        {Integer.to_string(session_id), build_targets(targets)}
      end)

    {:ok, Topic.new(agents, %{ref: ref})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:agent, session_id, targets}) do
    if is_nil(targets) do
      Topic.unset(topic, [], Integer.to_string(session_id))
    else
      Topic.set(topic, [Integer.to_string(session_id)], build_targets(targets))
    end
  end

  defp build_targets(targets) do
    Map.new(targets, fn {repository, repository_targets} ->
      # TODO: include type?
      target_names = Enum.map(repository_targets, fn {_, name} -> name end)
      {repository, target_names}
    end)
  end
end

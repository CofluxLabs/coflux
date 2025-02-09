defmodule Coflux.Topics.Environments do
  use Topical.Topic, route: ["projects", :project_id, "environments"]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    {:ok, environments, ref} = Orchestration.subscribe_environments(project_id, self())

    environments =
      Map.new(environments, fn {environment_id, environment} ->
        {Integer.to_string(environment_id), build_environment(environment)}
      end)

    {:ok, Topic.new(environments, %{ref: ref})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:environment, environment_id, environment}) do
    Topic.set(topic, [Integer.to_string(environment_id)], build_environment(environment))
  end

  defp process_notification(topic, {:state, environment_id, state}) do
    Topic.set(topic, [Integer.to_string(environment_id), :state], build_state(state))
  end

  defp build_environment(environment) do
    %{
      name: environment.name,
      baseId: environment.base_id,
      state: build_state(environment.state)
    }
  end

  defp build_state(state) do
    case state do
      :active -> "active"
      :paused -> "paused"
      :archived -> "archived"
    end
  end
end

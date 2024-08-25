defmodule Coflux.Topics.Environments do
  use Topical.Topic, route: ["projects", :project_id, "environments"]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    {:ok, environments, ref} = Orchestration.subscribe_environments(project_id, self())

    environments =
      Map.new(environments, fn {name, environment} ->
        {name, build_environment(environment)}
      end)

    {:ok, Topic.new(environments, %{ref: ref})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:environment, name, environment}) do
    Topic.set(topic, [name], build_environment(environment))
  end

  defp build_environment(environment) do
    %{
      base: environment.base,
      archived: environment.archived
    }
  end
end

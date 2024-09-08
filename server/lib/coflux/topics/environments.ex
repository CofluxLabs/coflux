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

  defp build_environment(environment) do
    %{
      name: environment.name,
      baseId: environment.base_id,
      pools: Map.new(environment.pools, &build_pool/1),
      status: environment.status
    }
  end

  defp build_pool({name, pool}) do
    {name,
     %{
       repositories: pool.repositories,
       provides: pool.provides,
       launcher: if(pool.launcher, do: Atom.to_string(pool.launcher.type), else: nil)
     }}
  end
end

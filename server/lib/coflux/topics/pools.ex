defmodule Coflux.Topics.Pools do
  use Topical.Topic, route: ["projects", :project_id, "pools", :environment_id]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))

    {:ok, pools, ref} =
      Orchestration.subscribe_pools(project_id, environment_id, self())

    value = build_value(pools)

    {:ok, Topic.new(value, %{ref: ref})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:pools, pools}) do
    Topic.set(topic, [], build_value(pools))
  end

  defp build_value(pools) do
    Map.new(pools, fn {key, pool} ->
      {key, build_pool(pool)}
    end)
  end

  defp build_pool(pool) do
    %{
      repositories: pool.repositories,
      provides: pool.provides,
      launcher: build_launcher(pool.launcher)
    }
  end

  defp build_launcher(launcher) do
    case launcher.type do
      :docker -> Map.take(launcher, [:type, :image])
    end
  end
end

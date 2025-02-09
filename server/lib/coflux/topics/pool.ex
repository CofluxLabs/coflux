defmodule Coflux.Topics.Pool do
  use Topical.Topic, route: ["projects", :project_id, "pools", :environment_id, :pool_name]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))
    pool_name = Keyword.fetch!(params, :pool_name)

    case Orchestration.subscribe_pool(project_id, environment_id, pool_name, self()) do
      {:ok, pool, launches, ref} ->
        {:ok,
         Topic.new(
           %{
             pool: build_pool(pool),
             launches:
               Map.new(launches, fn {launch_id, launch} ->
                 {Integer.to_string(launch_id), build_launch(launch)}
               end)
           },
           %{ref: ref}
         )}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:updated, pool}) do
    Topic.set(topic, [:pool], build_pool(pool))
  end

  defp process_notification(topic, {:launch, launch_id, starting_at}) do
    Topic.set(topic, [:launches, Integer.to_string(launch_id)], %{
      startingAt: starting_at,
      startedAt: nil,
      startError: nil,
      stoppingAt: nil,
      stopError: nil,
      deactivatedAt: nil,
      state: :active,
      connected: nil
    })
  end

  defp process_notification(topic, {:launch_result, launch_id, started_at, error}) do
    topic
    |> Topic.set([:launches, Integer.to_string(launch_id), :startedAt], started_at)
    |> Topic.set([:launches, Integer.to_string(launch_id), :startError], error)
  end

  defp process_notification(topic, {:launch_stopping, launch_id, stopping_at}) do
    Topic.set(topic, [:launches, Integer.to_string(launch_id), :stoppingAt], stopping_at)
  end

  defp process_notification(topic, {:launch_stop_result, launch_id, stopped_at, error}) do
    # TODO: don't set 'stopped_at' if error?
    topic
    |> Topic.set([:launches, Integer.to_string(launch_id), :stoppedAt], stopped_at)
    |> Topic.set([:launches, Integer.to_string(launch_id), :stopError], error)
  end

  defp process_notification(topic, {:launch_deactivated, launch_id, deactivated_at}) do
    Topic.set(topic, [:launches, Integer.to_string(launch_id), :deactivatedAt], deactivated_at)
  end

  defp process_notification(topic, {:launch_state, launch_id, state}) do
    Topic.set(topic, [:launches, Integer.to_string(launch_id), :state], state)
  end

  defp process_notification(topic, {:launch_connected, launch_id, connected}) do
    Topic.set(topic, [:launches, Integer.to_string(launch_id), :connected], connected)
  end

  defp build_launcher(launcher) do
    case launcher.type do
      :docker ->
        %{
          type: "docker",
          image: launcher.image
        }
    end
  end

  defp build_pool(pool) do
    if pool do
      %{
        repositories: pool.repositories,
        provides: pool.provides,
        # TODO: include launcher ID?
        launcher: if(pool.launcher, do: build_launcher(pool.launcher))
      }
    end
  end

  defp build_launch(launch) do
    %{
      # TODO: launcher ID? (and/or launcher?)
      startingAt: launch.starting_at,
      startedAt: launch.started_at,
      startError: launch.start_error,
      stoppingAt: launch.stopping_at,
      stopError: launch.stop_error,
      deactivatedAt: launch.deactivated_at,
      state: launch.state,
      connected: launch.connected
    }
  end
end

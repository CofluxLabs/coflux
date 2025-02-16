defmodule Coflux.Topics.Sessions do
  use Topical.Topic, route: ["projects", :project_id, "sessions", :environment_id]

  alias Coflux.Orchestration

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))

    {:ok, sessions, ref} = Orchestration.subscribe_sessions(project_id, environment_id, self())

    sessions =
      Map.new(sessions, fn {session_id, session} ->
        {Integer.to_string(session_id), build_session(session)}
      end)

    {:ok, Topic.new(sessions, %{ref: ref})}
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    topic = Enum.reduce(notifications, topic, &process_notification(&2, &1))
    {:ok, topic}
  end

  defp process_notification(topic, {:session, session_id, session}) do
    if is_nil(session) do
      Topic.unset(topic, [], Integer.to_string(session_id))
    else
      Topic.set(topic, [Integer.to_string(session_id)], build_session(session))
    end
  end

  defp process_notification(topic, {:connected, session_id, connected}) do
    Topic.set(topic, [Integer.to_string(session_id), :connected], connected)
  end

  defp process_notification(topic, {:executions, session_id, executions}) do
    Topic.set(topic, [Integer.to_string(session_id), :executions], executions)
  end

  defp build_session(session) do
    %{
      connected: session.connected,
      executions: session.executions,
      poolName: session.pool_name
    }
  end
end

defmodule Coflux.Project.Topics.RunLogs do
  use Topical.Topic, route: "projects/:project_id/runs/:run_id/logs"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    run_id = Keyword.fetch!(params, :run_id)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.Attempt, Models.LogMessage]
      )

    with {:ok, attempts} <- Store.get_attempts(project_id, run_id),
         execution_ids = Enum.map(attempts, & &1.execution_id),
         {:ok, log_messages} <- Store.get_log_messages(project_id, execution_ids) do
      result =
        Map.new(log_messages, fn log_message ->
          {log_message.id, build_log_message(log_message)}
        end)

      execution_ids = MapSet.new(attempts, & &1.execution_id)
      topic = Topic.new(result, %{run_id: run_id, execution_ids: execution_ids})

      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Attempt{} = attempt}, topic) do
    if attempt.run_id == topic.state.run_id do
      topic = update_in(topic.state.execution_ids, &MapSet.put(&1, attempt.execution_id))
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.LogMessage{} = log_message}, topic) do
    if log_message.execution_id in topic.state.execution_ids do
      topic = Topic.set(topic, [log_message.execution_id], build_log_message(log_message))
      {:ok, topic}
    else
      {:ok, topic}
    end
  end

  defp build_log_message(log_message) do
    %{
      executionId: log_message.execution_id,
      level: log_message.level,
      message: log_message.message,
      createdAt: log_message.created_at
    }
  end
end

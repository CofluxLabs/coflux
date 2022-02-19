defmodule Coflux.Project.Observer.Topics.RunLogs do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Attempt, Models.LogMessage]

  def load(project_id, [run_id]) do
    with {:ok, attempts} <- Store.get_attempts(project_id, run_id),
         execution_ids = Enum.map(attempts, & &1.execution_id),
         {:ok, log_messages} <- Store.get_log_messages(project_id, execution_ids) do
      result =
        Map.new(log_messages, fn log_message ->
          {log_message.id, Map.take(log_message, [:execution_id, :level, :message, :created_at])}
        end)

      execution_ids = MapSet.new(attempts, & &1.execution_id)

      {:ok, result, %{run_id: run_id, execution_ids: execution_ids}}
    end
  end

  def handle_insert(%Models.Attempt{} = attempt, _value, state) do
    if attempt.run_id == state.run_id do
      state = Map.update!(state, :execution_ids, &MapSet.put(&1, attempt.execution_id))
      {:ok, [], state}
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.LogMessage{} = log_message, _value, state) do
    if log_message.execution_id in state.execution_ids do
      {:ok,
       [
         {[log_message.execution_id],
          Map.take(log_message, [:execution_id, :level, :message, :created_at])}
       ], state}
    else
      {:ok, [], state}
    end
  end
end

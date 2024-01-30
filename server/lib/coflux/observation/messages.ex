defmodule Coflux.Observation.Messages do
  import Coflux.Store

  def put_messages(db, external_run_id, messages) do
    with_transaction(db, fn ->
      {:ok, run_id} = get_or_create_run(db, external_run_id)

      Enum.each(messages, fn {execution_id, timestamp, level, template, labels} ->
        {:ok, template_id} = get_or_create_template(db, template)

        {:ok, _} =
          insert_one(db, :messages, %{
            run_id: run_id,
            execution_id: execution_id,
            timestamp: timestamp,
            level: encode_level(level),
            template_id: template_id,
            labels: Jason.encode!(labels)
          })
      end)
    end)
  end

  def get_messages(db, external_run_id) do
    {:ok, run_id} = get_run_id(db, external_run_id)

    case query(
           db,
           "SELECT execution_id, timestamp, level, template_id, labels FROM messages WHERE run_id = ?1",
           {run_id}
         ) do
      {:ok, messages} ->
        messages =
          Enum.map(messages, fn {execution_id, timestamp, level, template_id, labels} ->
            # TODO: batch?
            {:ok, template} = get_template_by_id(db, template_id)
            {execution_id, timestamp, decode_level(level), template, Jason.decode!(labels)}
          end)

        {:ok, messages}
    end
  end

  defp get_template_by_id(db, template_id) do
    case query_one(db, "SELECT template FROM message_templates WHERE id = ?1", {template_id}) do
      {:ok, {template}} -> {:ok, template}
    end
  end

  defp get_run_id(db, external_id) do
    case query_one(db, "SELECT id FROM runs WHERE external_id = ?1", {external_id}) do
      {:ok, {run_id}} -> {:ok, run_id}
      {:ok, nil} -> {:ok, nil}
    end
  end

  defp get_or_create_run(db, external_id) do
    case get_run_id(db, external_id) do
      {:ok, nil} ->
        case insert_one(db, :runs, %{external_id: external_id}) do
          {:ok, run_id} ->
            {:ok, run_id}
        end

      {:ok, run_id} ->
        {:ok, run_id}
    end
  end

  defp get_or_create_template(db, template) do
    case query_one(db, "SELECT id FROM message_templates WHERE template = ?1", {template}) do
      {:ok, {template_id}} ->
        {:ok, template_id}

      {:ok, nil} ->
        case insert_one(db, :message_templates, %{template: template}) do
          {:ok, template_id} ->
            {:ok, template_id}
        end
    end
  end

  defp encode_level(level) do
    case level do
      :stdout -> 0
      :stderr -> 1
      :debug -> 2
      :info -> 3
      :warning -> 4
      :error -> 5
    end
  end

  defp decode_level(level) do
    case level do
      0 -> :stdout
      1 -> :stderr
      2 -> :debug
      3 -> :info
      4 -> :warning
      5 -> :error
    end
  end
end

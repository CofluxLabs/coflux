defmodule Coflux.Topics.Logs do
  use Topical.Topic,
    route: ["projects", :project_id, "environments", :environment_name, "runs", :run_id, "logs"]

  alias Coflux.Logging

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)
    run_id = Keyword.fetch!(params, :run_id)

    case Logging.subscribe(project_id, environment_name, run_id, self()) do
      {:ok, _ref, messages} ->
        topic =
          messages
          |> Enum.map(&encode_message/1)
          |> Topic.new()

        {:ok, topic}
    end
  end

  def handle_info({:messages, _ref, messages}, topic) do
    topic =
      Enum.reduce(messages, topic, fn message, topic ->
        Topic.insert(topic, [], encode_message(message))
      end)

    {:ok, topic}
  end

  defp encode_message({execution_id, timestamp, level, content}) do
    [execution_id, timestamp, encode_level(level), content]
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
end

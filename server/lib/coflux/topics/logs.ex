defmodule Coflux.Topics.Logs do
  use Topical.Topic, route: ["projects", :project_id, "runs", :run_id, "logs", :environment_id]

  alias Coflux.{Observation, Orchestration}

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    run_id = Keyword.fetch!(params, :run_id)
    environment_id = String.to_integer(Keyword.fetch!(params, :environment_id))

    case Observation.subscribe(project_id, run_id, self()) do
      {:ok, _ref, messages} ->
        case Orchestration.subscribe_run(project_id, run_id, self()) do
          {:ok, _run, _parent, steps, _ref} ->
            run_environment_id =
              steps
              |> Map.values()
              |> Enum.reject(& &1.parent_id)
              |> Enum.min_by(& &1.created_at)
              |> Map.fetch!(:executions)
              |> Map.values()
              |> Enum.min_by(& &1.created_at)
              |> Map.fetch!(:environment_id)

            environment_ids = Enum.uniq([run_environment_id, environment_id])

            execution_ids =
              steps
              |> Map.values()
              |> Enum.flat_map(fn step ->
                step.executions
                |> Map.values()
                |> Enum.filter(&(&1.environment_id in environment_ids))
                |> Enum.map(& &1.execution_id)
              end)
              |> MapSet.new()

            topic =
              messages
              |> Enum.filter(&(elem(&1, 0) in execution_ids))
              |> Enum.map(&encode_message/1)
              |> Topic.new(%{
                environment_ids: environment_ids,
                execution_ids: execution_ids
              })

            {:ok, topic}
        end
    end
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    execution_ids =
      Enum.reduce(notifications, topic.state.execution_ids, fn notification, execution_ids ->
        case notification do
          {:step, _, _, _, _, _, _, _, _, execution_id, environment_id, _} ->
            if environment_id in topic.state.environment_ids do
              MapSet.put(execution_ids, execution_id)
            else
              execution_ids
            end

          {:execution, _, _, execution_id, environment_id, _, _} ->
            if environment_id in topic.state.environment_ids do
              MapSet.put(execution_ids, execution_id)
            else
              execution_ids
            end

          _other ->
            execution_ids
        end
      end)

    topic = put_in(topic.state.execution_ids, execution_ids)

    {:ok, topic}
  end

  def handle_info({:messages, _ref, messages}, topic) do
    encoded =
      messages
      |> Enum.filter(&(elem(&1, 0) in topic.state.execution_ids))
      |> Enum.map(&encode_message/1)

    topic = Topic.insert(topic, [], encoded)
    {:ok, topic}
  end

  defp encode_message({execution_id, timestamp, level, template, labels}) do
    [execution_id, timestamp, encode_level(level), template, labels]
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

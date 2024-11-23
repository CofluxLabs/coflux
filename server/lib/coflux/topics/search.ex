defmodule Coflux.Topics.Search do
  alias Coflux.Orchestration
  use Topical.Topic, route: ["projects", :project_id, "search", :environment_id]

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_id = Keyword.fetch!(params, :environment_id)

    case Orchestration.subscribe_targets(project_id, environment_id, self()) do
      {:ok, targets, _ref} ->
        topic = Topical.Topic.new(nil, %{targets: targets})
        {:ok, topic}
    end
  end

  def handle_info({:topic, _ref, notifications}, topic) do
    # TODO: update index
    {:ok, topic}
  end

  def handle_execute("query", {query}, topic, _context) do
    query_parts = String.split(query)

    matches =
      if Enum.any?(query_parts) do
        topic.state
        |> generate_candidates()
        |> Enum.map(fn {candidate, candidate_parts} ->
          {score_candidate(candidate_parts, query_parts), candidate}
        end)
        |> Enum.filter(fn {score, _match} -> score > 0 end)
        |> Enum.sort_by(fn {score, _match} -> score end, :desc)
        |> Enum.take(20)
        |> Enum.map(fn {score, match} ->
          Map.put(build_match(match), :score, score)
        end)
      else
        []
      end

    {:ok, matches, topic}
  end

  defp generate_candidates(index) do
    Enum.flat_map(index.targets, fn {repository_name, repository} ->
      repository_name_parts = [repository_name | String.split(repository_name, ["_", "."])]

      Enum.concat([
        [{{:repository, repository_name}, [repository_name]}],
        Enum.flat_map(%{workflows: :workflow, sensors: :sensor}, fn {key, type} ->
          repository
          |> Map.fetch!(key)
          |> Enum.map(fn target_name ->
            target_name_parts = [target_name | String.split(target_name, "_")]
            target_parts = Enum.concat(repository_name_parts, target_name_parts)
            {{type, repository_name, target_name}, target_parts}
          end)
        end),
        repository
        |> Map.get(:steps, %{})
        |> Enum.map(fn {target_name, {run_external_id, step_external_id, step_attempt}} ->
          target_name_parts = [target_name | String.split(target_name, "_")]
          step_parts = Enum.concat(repository_name_parts, target_name_parts)

          {{:step, repository_name, target_name, run_external_id, step_external_id, step_attempt},
           step_parts}
        end)
      ])
    end)
    |> Enum.map(fn {candidate, parts} ->
      parts = parts |> Enum.reject(&(&1 == "")) |> Enum.uniq()
      {candidate, parts}
    end)
  end

  defp score_candidate(candidate_parts, query_parts) do
    query_parts
    |> Enum.map(fn query_part ->
      candidate_parts
      |> Enum.map(&String.jaro_distance(&1, query_part))
      |> Enum.max()
    end)
    |> Enum.product()
  end

  defp build_match(match) do
    case match do
      {:repository, repository_name} ->
        %{
          type: "repository",
          name: repository_name
        }

      {:workflow, repository_name, target_name} ->
        %{
          type: "workflow",
          repository: repository_name,
          name: target_name
        }

      {:sensor, repository_name, target_name} ->
        %{
          type: "sensor",
          repository: repository_name,
          name: target_name
        }

      {:step, step_repository_name, step_target_name, run_external_id, step_external_id,
       step_attempt} ->
        %{
          type: "step",
          repository: step_repository_name,
          name: step_target_name,
          runId: run_external_id,
          stepId: step_external_id,
          attempt: step_attempt
        }
    end
  end
end

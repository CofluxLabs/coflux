defmodule Coflux.Handlers.Runs do
  import Coflux.Handlers.Utils

  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:run], opts)
  end

  defp handle(req, "GET", project_id, run_id, opts) do
    run = Project.get_run(project_id, run_id)

    result = %{
      "id" => run.id,
      "task" => %{
        "id" => run.task.id,
        "repository" => run.task.repository,
        "target" => run.task.target,
        "version" => run.task.version
      },
      "steps" =>
        Enum.map(run.steps, fn step ->
          %{
            "id" => step.id,
            "parentId" => step.parent_id,
            "repository" => step.repository,
            "target" => step.target,
            "createdAt" => step.created_at,
            "cachedStep" =>
              step.cached_step &&
                %{
                  "id" => step.cached_step.id,
                  "runId" => step.cached_step.run_id
                },
            "arguments" =>
              Enum.map(step.arguments, fn argument ->
                %{
                  # TODO
                  "type" => argument.type,
                  "value" => argument.value
                }
              end),
            "executions" =>
              Enum.map(step.executions, fn execution ->
                %{
                  "id" => execution.id,
                  "createdAt" => execution.created_at,
                  "dependencyIds" => Enum.map(execution.dependencies, & &1.dependency_id),
                  "assignedAt" => execution.assignment && execution.assignment.created_at,
                  "result" =>
                    execution.result &&
                      %{
                        # TODO
                        "type" => execution.result.type,
                        "value" => execution.result.value,
                        "createdAt" => execution.result.created_at
                      }
                }
              end)
          }
        end)
    }

    req = json_response(req, result)
    {:ok, req, opts}
  end
end

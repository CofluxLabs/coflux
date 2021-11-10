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
      "steps" =>
        Enum.map(run.steps, fn step ->
          %{
            "id" => step.id,
            "repository" => step.repository,
            "target" => step.target,
            "createdAt" => step.created_at,
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
                  "childStepIds" => Enum.map(execution.child_steps, & &1.id),
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

defmodule Coflux.Handlers.TaskRuns do
  import Coflux.Handlers.Utils

  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:task], opts)
  end

  defp handle(req, "POST", project_id, task_id, opts) do
    case Project.schedule_task(project_id, task_id) do
      {:ok, run_id, _execution_id} ->
        req = json_response(req, %{"id" => run_id})
        {:ok, req, opts}
    end
  end

  defp handle(req, "GET", project_id, task_id, opts) do
    result =
      project_id
      |> Project.list_task_runs(task_id)
      |> Enum.map(fn run ->
        %{
          "id" => run.id,
          "createdAt" => run.created_at
        }
      end)

    req = json_response(req, result)
    {:ok, req, opts}
  end
end

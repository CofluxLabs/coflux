defmodule Coflux.Handlers.Tasks do
  import Coflux.Handlers.Utils

  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:task], opts)
  end

  defp handle(req, "GET", project_id, nil, opts) do
    result =
      project_id
      |> Project.list_tasks()
      |> Enum.map(fn task ->
        %{
          "id" => task.id,
          "repository" => task.repository,
          "version" => task.version,
          "target" => task.target
        }
      end)

    req = json_response(req, result)
    {:ok, req, opts}
  end

  defp handle(req, "GET", project_id, task_id, opts) do
    task = Project.get_task(project_id, task_id)

    result = %{
      "id" => task.id,
      "repository" => task.repository,
      "version" => task.version,
      "target" => task.target
    }

    req = json_response(req, result)
    {:ok, req, opts}
  end
end

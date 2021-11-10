defmodule Coflux.Handlers.Tasks do
  import Coflux.Handlers.Utils
  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    handle(req, :cowboy_req.method(req), bindings[:project], opts)
  end

  defp handle(req, "GET", project_id, opts) do
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
end

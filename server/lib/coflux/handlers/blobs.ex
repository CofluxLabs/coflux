defmodule Coflux.Handlers.Blobs do
  import Coflux.Handlers.Utils

  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:key], opts)
  end

  defp handle(req, "GET", project_id, key, opts) do
    case Project.get_blob(project_id, key) do
      {:ok, content} ->
        req = :cowboy_req.reply(200, %{"content-type" => "application/json"}, content, req)
        {:ok, req, opts}
    end
  end

  defp handle(req, "PUT", project_id, key, opts) do
    # TODO: handle more
    case :cowboy_req.read_body(req) do
      {:ok, content, req} ->
        case Project.put_blob(project_id, key, content) do
          :ok ->
            req = :cowboy_req.reply(204, req)
            {:ok, req, opts}
        end
    end
  end
end

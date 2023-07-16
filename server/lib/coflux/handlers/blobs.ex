defmodule Coflux.Handlers.Blobs do
  import Coflux.Handlers.Utils

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:key], opts)
  end

  defp handle(req, "GET", key, opts) do
    case get_blob(key) do
      {:ok, content} ->
        req = :cowboy_req.reply(200, %{"content-type" => "application/json"}, content, req)
        {:ok, req, opts}
    end
  end

  defp handle(req, "PUT", key, opts) do
    # TODO: handle more
    case :cowboy_req.read_body(req) do
      {:ok, content, req} ->
        case put_blob(key, content) do
          :ok ->
            req = :cowboy_req.reply(204, req)
            {:ok, req, opts}
        end
    end
  end

  defp blob_path(key) do
    "blobs/#{key}"
  end

  defp get_blob(key) do
    {:ok, File.read!(blob_path(key))}
  end

  defp put_blob(key, content) do
    path = blob_path(key)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end
end

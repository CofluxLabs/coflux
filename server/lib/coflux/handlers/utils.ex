defmodule Coflux.Handlers.Utils do
  def set_cors_headers(req) do
    :cowboy_req.set_resp_headers(
      %{
        "access-control-allow-origin" => "*",
        "access-control-allow-methods" => "OPTIONS, GET, POST, PUT, PATCH, DELETE",
        "access-control-allow-headers" => "content-type,authorization",
        "access-control-max-age" => "86400"
      },
      req
    )
  end

  def json_response(req, status \\ 200, result) do
    :cowboy_req.reply(
      status,
      %{"content-type" => "application/json"},
      Jason.encode!(result),
      req
    )
  end

  def read_json_body(req) do
    case :cowboy_req.read_body(req) do
      {:ok, data, req} ->
        with {:ok, result} <- Jason.decode(data) do
          {:ok, result, req}
        end
    end
  end
end

defmodule Coflux.Handlers.Utils do
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

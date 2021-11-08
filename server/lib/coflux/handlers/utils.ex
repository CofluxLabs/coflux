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

  def parse_result(result) do
    case result do
      ["raw", value] -> {:raw, value}
      ["res", execution_id] -> {:res, execution_id}
    end
  end

  def compose_result(result) do
    case result do
      {:raw, value} -> ["raw", value]
      {:res, execution_id} -> ["res", execution_id]
    end
  end
end

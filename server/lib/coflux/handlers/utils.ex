defmodule Coflux.Handlers.Utils do
  def json_response(req, status \\ 200, result) do
    :cowboy_req.reply(
      status,
      %{"content-type" => "application/json"},
      Jason.encode!(result),
      req
    )
  end
end

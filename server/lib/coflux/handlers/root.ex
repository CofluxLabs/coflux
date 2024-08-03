defmodule Coflux.Handlers.Root do
  def init(req, opts) do
    req =
      :cowboy_req.reply(
        200,
        %{"content-type" => "text/html"},
        """
        <!DOCTYPE html>
        <html lang="en">
        <link rel="stylesheet" href="/static/app.css" />
        <link rel="icon" href="/static/icon.svg" />
        <div id="root"></div>
        <script src="/static/app.js"></script>
        </html>
        """,
        req
      )

    {:ok, req, opts}
  end
end

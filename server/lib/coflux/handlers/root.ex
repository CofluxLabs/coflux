defmodule Coflux.Handlers.Root do
  import Coflux.Handlers.Utils

  @version Mix.Project.config()[:app] |> Application.spec(:vsn) |> to_string()

  def init(req, opts) do
    req = json_response(req, %{server: "Coflux", version: @version})
    {:ok, req, opts}
  end
end

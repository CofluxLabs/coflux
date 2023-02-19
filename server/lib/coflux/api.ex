defmodule Coflux.Api do
  alias Coflux.Handlers
  alias Topical.Adapters.Cowboy.WebsocketHandler, as: TopicalHandler

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)
    trans_opts = %{socket_opts: [port: port]}
    proto_opts = %{env: %{dispatch: dispatch()}, connection_type: :supervisor}
    :ranch.child_spec(:http, :ranch_tcp, trans_opts, :cowboy_clear, proto_opts)
  end

  defp dispatch() do
    :cowboy_router.compile([
      {:_,
       [
         {"/", Handlers.Root, []},
         # TODO: flatten?
         {"/projects/:project/blobs/:key", Handlers.Blobs, []},
         {"/projects/:project/agent", Handlers.Agent, []},
         {"/topics", TopicalHandler, registry: Coflux.TopicalRegistry}
       ]}
    ])
  end
end

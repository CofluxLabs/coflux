defmodule Coflux.Api do
  alias Coflux.Handlers

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)
    trans_opts = :ranch.normalize_opts(port: port)
    proto_opts = %{env: %{dispatch: dispatch()}, connection_type: :supervisor}
    IO.puts("Starting API on port #{port}...")
    :ranch.child_spec(:http, :ranch_tcp, trans_opts, :cowboy_clear, proto_opts)
  end

  defp dispatch() do
    :cowboy_router.compile([
      {:_,
       [
         {"/", Handlers.Root, []}
       ]}
    ])
  end
end

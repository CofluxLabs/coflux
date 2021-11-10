defmodule Coflux.Api do
  alias Coflux.Handlers

  def child_spec(opts) do
    port = Keyword.fetch!(opts, :port)

    IO.puts("Starting API on port #{port}...")

    trans_opts = %{socket_opts: [port: port]}
    proto_opts = %{env: %{dispatch: dispatch()}, connection_type: :supervisor}
    :ranch.child_spec(:http, :ranch_tcp, trans_opts, :cowboy_clear, proto_opts)
  end

  defp dispatch() do
    :cowboy_router.compile([
      {:_,
       [
         {"/", Handlers.Root, []},
         {"/projects/[:project]/tasks", Handlers.Tasks, []},
         {"/projects/[:project]/agents", Handlers.Agents, []},
         {"/projects/[:project]/executions/[:execution]/children", Handlers.ExecutionChildren, []},
         {"/projects/[:project]/executions/[:execution]/result", Handlers.ExecutionResult, []}
       ]}
    ])
  end
end

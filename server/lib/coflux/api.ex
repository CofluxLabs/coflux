defmodule Coflux.Api do
  alias Coflux.Handlers

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
         {"/projects/:project/tasks/[:task]", Handlers.Tasks, []},
         {"/projects/:project/tasks/:task/runs", Handlers.TaskRuns, []},
         {"/projects/:project/runs/[:run]", Handlers.Runs, []},
         {"/projects/:project/agents/[:agent]", Handlers.Agents, []},
         {"/projects/:project/blobs/:key", Handlers.Blobs, []},
         {"/projects/:project/agent", Handlers.Agent, []},
         {"/projects/:project/events", Handlers.Events, []}
       ]}
    ])
  end
end

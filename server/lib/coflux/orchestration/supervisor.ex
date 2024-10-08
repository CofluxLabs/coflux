defmodule Coflux.Orchestration.Supervisor do
  alias Coflux.Orchestration.Server

  @registry __MODULE__.Registry
  @supervisor __MODULE__.Supervisor

  def child_spec(opts) do
    Supervisor.child_spec(
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :supervisor
      },
      opts
    )
  end

  def start_link() do
    children = [
      {Registry, name: @registry, keys: :unique},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_all)
  end

  def get_server(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec =
          {Server,
           id: Server, name: {:via, Registry, {@registry, project_id}}, project_id: project_id}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}
        end
    end
  end
end

defmodule Coflux.Observation.Supervisor do
  alias Coflux.Observation.Server

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

  def get_server(project_id, environment) do
    key = {project_id, environment}

    case Registry.lookup(@registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec =
          {Server,
           id: Server,
           name: {:via, Registry, {@registry, key}},
           project_id: project_id,
           environment: environment}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}
        end
    end
  end
end

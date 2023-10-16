defmodule Coflux.Logging.Supervisor do
  alias Coflux.Logging.Server

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

  def get_server(project_id, environment, run_id) do
    key = {project_id, environment, run_id}

    case Registry.lookup(@registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec =
          {Server,
           id: Server,
           name: {:via, Registry, {@registry, key}},
           project_id: project_id,
           environment: environment,
           run_id: run_id}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            {:ok, pid}
        end
    end
  end
end

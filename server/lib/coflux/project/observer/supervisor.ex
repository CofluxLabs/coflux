defmodule Coflux.Project.Observer.Supervisor do
  alias Coflux.Project.Observer.Server

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
    Supervisor.start_link(
      [
        {Registry, name: @registry, keys: :unique},
        {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
      ],
      strategy: :one_for_all
    )
  end

  def get_server(project_id, topic, arguments) do
    key = {project_id, topic, arguments}

    case Registry.lookup(@registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = {Server, name: {:via, Registry, {@registry, key}}, id: key}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} -> {:ok, pid}
        end
    end
  end
end

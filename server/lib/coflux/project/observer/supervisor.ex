defmodule Coflux.Project.Observer.Supervisor do
  alias Coflux.Project.Observer

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

  def get_server(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = {Observer, name: {:via, Registry, {@registry, project_id}}, id: project_id}

        case DynamicSupervisor.start_child(@supervisor, spec) do
          {:ok, pid} -> {:ok, pid}
        end
    end
  end
end

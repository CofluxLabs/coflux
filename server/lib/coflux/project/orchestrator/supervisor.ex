defmodule Coflux.Project.Orchestrator.Supervisor do
  alias Coflux.Project.Orchestrator.Server

  @registry __MODULE__.Registry
  @supervisor __MODULE__.Supervisor

  def child_spec(init_arg) do
    {project_ids, opts} = Keyword.pop!(init_arg, :project_ids)

    Supervisor.child_spec(
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, [project_ids]},
        type: :supervisor
      },
      opts
    )
  end

  def start_link(project_ids) do
    children = [
      {Registry, name: @registry, keys: :unique},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
    ]

    with {:ok, pid} <- Supervisor.start_link(children, strategy: :one_for_all) do
      Enum.each(project_ids, &start_server/1)
      {:ok, pid}
    end
  end

  def get_server(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        {:error, :not_found}
    end
  end

  defp start_server(project_id) do
    spec = {Server, name: {:via, Registry, {@registry, project_id}}, id: project_id}
    DynamicSupervisor.start_child(@supervisor, spec)
  end
end

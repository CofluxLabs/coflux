defmodule Coflux.Project do
  alias Coflux.Project.Server

  @registry Coflux.ProjectsRegistry
  @supervisor Coflux.ProjectsSupervisor

  def register(project_id, targets, pid) do
    call(project_id, {:register, targets, pid})
  end

  def schedule(project_id, target, arguments \\ [], from_execution_id \\ nil) do
    call(project_id, {:schedule, target, arguments, from_execution_id})
  end

  def put_result(project_id, execution_id, result) do
    call(project_id, {:put_result, execution_id, result})
  end

  def get_result(project_id, execution_id) do
    call(project_id, {:get_result, execution_id})
  end

  def execute(project_id, target, arguments \\ []) do
    case schedule(project_id, target, arguments) do
      {:ok, execution_id} ->
        case get_result(project_id, execution_id) do
          {:ok, result} ->
            case result do
              {:completed, value} ->
                {:ok, value}

              {:failed, message, _details} ->
                {:error, message}
            end
        end
    end
  end

  defp call(project_id, request) do
    with {:ok, pid} <- get_pid(project_id) do
      GenServer.call(pid, request, 10_000)
    end
  end

  defp get_pid(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        # TODO: check project exists
        opts = [name: {:via, Registry, {@registry, project_id}}, id: project_id]
        DynamicSupervisor.start_child(@supervisor, {Server, opts})
    end
  end
end

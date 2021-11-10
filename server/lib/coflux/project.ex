defmodule Coflux.Project do
  alias Coflux.Project.Store
  alias Coflux.Project.Supervisor, as: ProjectSupervisor

  def list_tasks(project_id) do
    Store.list_tasks(project_id)
  end

  def register(project_id, repository, version, targets, pid) do
    Store.create_tasks(project_id, repository, version, targets)
    call_server(project_id, {:register_targets, repository, version, targets, pid})
  end

  def schedule_task(project_id, task_id, arguments \\ []) do
    Store.schedule_task(project_id, task_id, arguments)
  end

  def schedule_child(project_id, parent_execution_id, repository, target, arguments \\ []) do
    Store.schedule_child(project_id, parent_execution_id, repository, target, arguments)
  end

  def put_result(project_id, execution_id, result) do
    Store.put_result(project_id, execution_id, result)
  end

  def get_result(project_id, execution_id) do
    # TODO: try to get from database first?
    call_server(project_id, {:get_result, execution_id})
  end

  defp call_server(project_id, request) do
    with {:ok, pid} <- ProjectSupervisor.get_server(project_id) do
      GenServer.call(pid, request, 10_000)
    end
  end
end

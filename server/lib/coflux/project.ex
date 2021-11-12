defmodule Coflux.Project do
  alias Coflux.Project.Store
  alias Coflux.Project.Supervisor, as: ProjectSupervisor

  def get_agents(project_id) do
    call_server(project_id, :get_agents)
  end

  def list_tasks(project_id) do
    Store.list_tasks(project_id)
  end

  def list_task_runs(project_id, task_id) do
    Store.list_task_runs(project_id, task_id)
  end

  def get_task(project_id, task_id) do
    Store.get_task(project_id, task_id)
  end

  def get_run(project_id, run_id) do
    Store.get_run(project_id, run_id)
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

  def acknowledge_exeutions(project_id, execution_ids) do
    Store.acknowledge_executions(project_id, execution_ids)
  end

  def put_result(project_id, execution_id, result) do
    Store.put_result(project_id, execution_id, result)
  end

  def get_result(project_id, execution_id, pid) do
    # TODO: try to get from database first?
    call_server(project_id, {:get_result, execution_id, pid})
  end

  defp call_server(project_id, request) do
    with {:ok, pid} <- ProjectSupervisor.get_server(project_id) do
      GenServer.call(pid, request, 10_000)
    end
  end
end

defmodule Coflux.Project do
  alias Coflux.Project.Store
  alias Coflux.Project.Orchestrator.Supervisor, as: OrchestratorSupervisor
  alias Coflux.Project.Observer.Supervisor, as: ObserverSupervisor

  def get_agents(project_id) do
    call_orchestrator(project_id, :get_agents)
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

  defp blob_path(project_id, key) do
    "blobs/#{project_id}/#{key}"
  end

  def get_blob(project_id, key) do
    {:ok, File.read!(blob_path(project_id, key))}
  end

  def put_blob(project_id, key, content) do
    path = blob_path(project_id, key)
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end

  def register(project_id, repository, version, targets, pid) do
    Store.create_tasks(project_id, repository, version, targets)
    call_orchestrator(project_id, {:register_targets, repository, version, targets, pid})
  end

  def schedule_task(project_id, task_id, arguments \\ []) do
    Store.schedule_task(project_id, task_id, arguments)
  end

  def schedule_child(
        project_id,
        parent_execution_id,
        repository,
        target,
        arguments \\ [],
        opts \\ []
      ) do
    Store.schedule_child(project_id, parent_execution_id, repository, target, arguments, opts)
  end

  def record_heartbeats(project_id, execution_ids) do
    Store.record_heartbeats(project_id, execution_ids)
  end

  def put_result(project_id, execution_id, result) do
    Store.put_result(project_id, execution_id, result)
  end

  def get_result(project_id, execution_id, from_execution_id \\ nil, pid) do
    if from_execution_id do
      Store.record_dependency(project_id, from_execution_id, execution_id)
    end

    # TODO: try to get from database first?
    call_orchestrator(project_id, {:get_result, execution_id, pid})
  end

  def subscribe(project_id, topic, pid) do
    call_observer(project_id, {:subscribe, topic, pid})
  end

  def unsubscribe(project_id, ref) do
    call_observer(project_id, {:unsubscribe, ref})
  end

  defp call_orchestrator(project_id, request) do
    with {:ok, pid} <- OrchestratorSupervisor.get_server(project_id) do
      GenServer.call(pid, request, 10_000)
    end
  end

  defp call_observer(project_id, request) do
    with {:ok, pid} <- ObserverSupervisor.get_server(project_id) do
      GenServer.call(pid, request, 10_000)
    end
  end
end

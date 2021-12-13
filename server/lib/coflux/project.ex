defmodule Coflux.Project do
  alias Coflux.Project.Store
  alias Coflux.Project.Orchestrator.Supervisor, as: OrchestratorSupervisor
  alias Coflux.Project.Observer.Supervisor, as: ObserverSupervisor

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

  def register(project_id, repository, version, manifest, pid) do
    Store.register_targets(project_id, repository, version, manifest)
    call_orchestrator(project_id, {:register_targets, repository, version, manifest, pid})
  end

  def schedule_task(project_id, repository, target, arguments \\ [], opts \\ []) do
    Store.schedule_task(project_id, repository, target, arguments, opts)
  end

  def schedule_step(project_id, parent_id, repository, target, arguments \\ [], opts \\ []) do
    Store.schedule_step(project_id, parent_id, repository, target, arguments, opts)
  end

  def record_heartbeats(project_id, executions) do
    Store.record_heartbeats(project_id, executions)
  end

  def put_result(project_id, execution_id, result) do
    Store.put_result(project_id, execution_id, result)
  end

  def put_cursor(project_id, execution_id, result) do
    Store.put_cursor(project_id, execution_id, result)
  end

  def get_result(project_id, execution_id, from \\ nil, pid) do
    if from do
      Store.record_dependency(project_id, from, execution_id)
    end

    # TODO: try to get from database first?
    call_orchestrator(project_id, {:get_result, execution_id, pid})
  end

  def get_run_result(project_id, run_id, pid) do
    initial_step = Store.get_run_initial_step(project_id, run_id)
    attempt = Store.get_step_latest_attempt(project_id, run_id, initial_step.id)
    get_result(project_id, attempt.execution_id, pid)
  end

  def activate_sensor(project_id, sensor_id, opts \\ []) do
    Store.activate_sensor(project_id, sensor_id, opts)
  end

  def deactivate_sensor(project_id, activation_id) do
    Store.deactivate_sensor(project_id, activation_id)
  end

  def log_message(project_id, execution_id, level, message) do
    Store.log_message(project_id, execution_id, level, message)
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

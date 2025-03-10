defmodule Coflux.Orchestration do
  alias Coflux.Orchestration

  def get_environments(project_id) do
    call_server(project_id, :get_environments)
  end

  def create_environment(project_id, name, base_id) do
    call_server(project_id, {:create_environment, name, base_id})
  end

  def update_environment(project_id, environment_id, updates) do
    call_server(project_id, {:update_environment, environment_id, updates})
  end

  def pause_environment(project_id, environment_name) do
    call_server(project_id, {:pause_environment, environment_name})
  end

  def resume_environment(project_id, environment_name) do
    call_server(project_id, {:resume_environment, environment_name})
  end

  def archive_environment(project_id, environment_name) do
    call_server(project_id, {:archive_environment, environment_name})
  end

  def update_pool(project_id, environment_name, pool_name, pool) do
    call_server(project_id, {:update_pool, environment_name, pool_name, pool})
  end

  def stop_agent(project_id, environment_name, agent_id) do
    call_server(project_id, {:stop_agent, environment_name, agent_id})
  end

  def resume_agent(project_id, environment_name, agent_id) do
    call_server(project_id, {:resume_agent, environment_name, agent_id})
  end

  def register_manifests(project_id, environment_name, manifests) do
    call_server(project_id, {:register_manifests, environment_name, manifests})
  end

  def archive_repository(project_id, environment_name, repository_name) do
    call_server(project_id, {:archive_repository, environment_name, repository_name})
  end

  def get_workflow(project_id, environment_name, repository, target_name) do
    call_server(project_id, {:get_workflow, environment_name, repository, target_name})
  end

  def start_session(project_id, environment_name, agent_id, provides, concurrency, pid) do
    call_server(
      project_id,
      {:start_session, environment_name, agent_id, provides, concurrency, pid}
    )
  end

  def resume_session(project_id, session_id, pid) do
    call_server(project_id, {:resume_session, session_id, pid})
  end

  def declare_targets(project_id, session_id, targets) do
    call_server(project_id, {:declare_targets, session_id, targets})
  end

  def start_run(project_id, repository, target, type, arguments, opts \\ []) do
    call_server(project_id, {:start_run, repository, target, type, arguments, opts})
  end

  def schedule_step(project_id, parent_id, repository, target, type, arguments, opts \\ []) do
    call_server(
      project_id,
      {:schedule_step, parent_id, repository, target, type, arguments, opts}
    )
  end

  def cancel_execution(project_id, execution_id) do
    call_server(project_id, {:cancel_execution, execution_id})
  end

  def rerun_step(project_id, step_id, environment_name) do
    call_server(project_id, {:rerun_step, step_id, environment_name})
  end

  def record_heartbeats(project_id, executions, session_id) do
    call_server(project_id, {:record_heartbeats, executions, session_id})
  end

  def notify_terminated(project_id, execution_ids) do
    call_server(project_id, {:notify_terminated, execution_ids})
  end

  def record_checkpoint(project_id, execution_id, arguments) do
    call_server(project_id, {:record_checkpoint, execution_id, arguments})
  end

  def record_result(project_id, execution_id, result) do
    call_server(project_id, {:record_result, execution_id, result})
  end

  def get_result(project_id, execution_id, from_execution_id, session_id, request_id) do
    call_server(
      project_id,
      {:get_result, execution_id, from_execution_id, session_id, request_id}
    )
  end

  def put_asset(project_id, execution_id, type, path, blob_key, size, metadata) do
    call_server(
      project_id,
      {:put_asset, execution_id, type, path, blob_key, size, metadata}
    )
  end

  def get_asset(project_id, asset_id, opts) do
    call_server(project_id, {:get_asset, asset_id, opts})
  end

  def record_logs(project_id, execution_id, messages) do
    call_server(project_id, {:record_logs, execution_id, messages})
  end

  def subscribe_environments(project_id, pid) do
    call_server(project_id, {:subscribe_environments, pid})
  end

  def subscribe_repositories(project_id, environment_id, pid) do
    call_server(project_id, {:subscribe_repositories, environment_id, pid})
  end

  def subscribe_repository(project_id, repository, environment_id, pid) do
    call_server(project_id, {:subscribe_repository, repository, environment_id, pid})
  end

  def subscribe_pools(project_id, environment_id, pid) do
    call_server(project_id, {:subscribe_pools, environment_id, pid})
  end

  def subscribe_pool(project_id, environment_id, pool_name, pid) do
    call_server(project_id, {:subscribe_pool, environment_id, pool_name, pid})
  end

  def subscribe_sessions(project_id, environment_id, pid) do
    call_server(project_id, {:subscribe_sessions, environment_id, pid})
  end

  def subscribe_workflow(project_id, repository, target, environment_id, pid) do
    call_server(project_id, {:subscribe_workflow, repository, target, environment_id, pid})
  end

  def subscribe_sensor(project_id, repository, target, environment_id, pid) do
    call_server(project_id, {:subscribe_sensor, repository, target, environment_id, pid})
  end

  def subscribe_run(project_id, run_id, pid) do
    call_server(project_id, {:subscribe_run, run_id, pid})
  end

  def subscribe_logs(project_id, run_id, pid) do
    call_server(project_id, {:subscribe_logs, run_id, pid})
  end

  def subscribe_targets(project_id, environment_id, pid) do
    call_server(project_id, {:subscribe_targets, environment_id, pid})
  end

  def unsubscribe(project_id, ref) do
    cast_server(project_id, {:unsubscribe, ref})
  end

  defp call_server(project_id, request) do
    case Orchestration.Supervisor.get_server(project_id) do
      {:ok, server} ->
        GenServer.call(server, request)
    end
  end

  defp cast_server(project_id, request) do
    case Orchestration.Supervisor.get_server(project_id) do
      {:ok, server} ->
        GenServer.cast(server, request)
    end
  end
end

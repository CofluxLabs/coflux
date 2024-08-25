defmodule Coflux.Orchestration do
  alias Coflux.Orchestration

  def register_environment(project_id, environment_name, base, archived \\ false) do
    call_server(project_id, {:register_environment, environment_name, base, archived})
  end

  def connect(project_id, session_id, environment, concurrency, pid) do
    call_server(project_id, {:connect, session_id, environment, concurrency, pid})
  end

  def register_targets(project_id, session_id, repository, targets) do
    call_server(project_id, {:register_targets, session_id, repository, targets})
  end

  def schedule_run(project_id, repository, target, arguments, opts \\ []) do
    call_server(project_id, {:schedule_run, repository, target, arguments, opts})
  end

  def schedule_task(project_id, parent_id, repository, target, arguments, opts \\ []) do
    call_server(project_id, {:schedule_task, parent_id, repository, target, arguments, opts})
  end

  def cancel_run(project_id, run_id) do
    call_server(project_id, {:cancel_run, run_id})
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

  def get_result(project_id, execution_id, from_execution_id \\ nil, session_id, request_id) do
    call_server(
      project_id,
      {:get_result, execution_id, from_execution_id, session_id, request_id}
    )
  end

  def put_asset(project_id, execution_id, type, path, blob_key, metadata) do
    call_server(
      project_id,
      {:put_asset, execution_id, type, path, blob_key, metadata}
    )
  end

  def get_asset(project_id, asset_id, from_execution_id \\ nil) do
    call_server(project_id, {:get_asset, asset_id, from_execution_id})
  end

  def subscribe_environments(project_id, pid) do
    call_server(project_id, {:subscribe_environments, pid})
  end

  def subscribe_repositories(project_id, environment_name, pid) do
    call_server(project_id, {:subscribe_repositories, environment_name, pid})
  end

  def subscribe_repository(project_id, repository, environment_name, pid) do
    call_server(project_id, {:subscribe_repository, repository, environment_name, pid})
  end

  def subscribe_agents(project_id, environment_name, pid) do
    call_server(project_id, {:subscribe_agents, environment_name, pid})
  end

  def subscribe_target(project_id, repository, target, environment_name, pid) do
    call_server(project_id, {:subscribe_target, repository, target, environment_name, pid})
  end

  def subscribe_run(project_id, run_id, pid) do
    call_server(project_id, {:subscribe_run, run_id, pid})
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

defmodule Coflux.Orchestration do
  alias Coflux.Orchestration

  def connect(project_id, environment, session_id, concurrency, pid) do
    call_server(project_id, environment, {:connect, session_id, concurrency, pid})
  end

  def register_targets(project_id, environment, session_id, repository, targets) do
    call_server(project_id, environment, {:register_targets, session_id, repository, targets})
  end

  def schedule(
        project_id,
        environment,
        repository,
        target,
        arguments,
        opts \\ []
      ) do
    call_server(
      project_id,
      environment,
      {:schedule, repository, target, arguments, opts}
    )
  end

  def cancel_run(project_id, environment, run_id) do
    call_server(project_id, environment, {:cancel_run, run_id})
  end

  def rerun_step(project_id, environment, step_id) do
    call_server(project_id, environment, {:rerun_step, step_id})
  end

  def record_heartbeats(project_id, environment, executions, session_id) do
    call_server(project_id, environment, {:record_heartbeats, executions, session_id})
  end

  def notify_terminated(project_id, environment, execution_ids) do
    call_server(project_id, environment, {:notify_terminated, execution_ids})
  end

  def record_result(project_id, environment, execution_id, result) do
    call_server(project_id, environment, {:record_result, execution_id, result})
  end

  def record_cursor(project_id, environment, execution_id, result) do
    call_server(project_id, environment, {:record_cursor, execution_id, result})
  end

  def get_result(project_id, environment, execution_id, from_execution_id \\ nil, pid) do
    call_server(project_id, environment, {:get_result, execution_id, from_execution_id, pid})
  end

  def lookup_runs(project_id, environment, execution_ids) do
    call_server(project_id, environment, {:lookup_runs, execution_ids})
  end

  def subscribe_repositories(project_id, environment, pid) do
    call_server(project_id, environment, {:subscribe_repositories, pid})
  end

  def subscribe_repository(project_id, environment, repository, pid) do
    call_server(project_id, environment, {:subscribe_repository, repository, pid})
  end

  def subscribe_agents(project_id, environment, pid) do
    call_server(project_id, environment, {:subscribe_agents, pid})
  end

  def subscribe_target(project_id, environment, repository, target, pid) do
    call_server(project_id, environment, {:subscribe_target, repository, target, pid})
  end

  def subscribe_run(project_id, environment, run_id, pid) do
    call_server(project_id, environment, {:subscribe_run, run_id, pid})
  end

  def unsubscribe(project_id, environment, ref) do
    cast_server(project_id, environment, {:unsubscribe, ref})
  end

  defp call_server(project_id, environment, request) do
    case Orchestration.Supervisor.get_server(project_id, environment) do
      {:ok, server} ->
        GenServer.call(server, request)
    end
  end

  defp cast_server(project_id, environment, request) do
    case Orchestration.Supervisor.get_server(project_id, environment) do
      {:ok, server} ->
        GenServer.cast(server, request)
    end
  end
end

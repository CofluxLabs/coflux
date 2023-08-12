defmodule Coflux.Handlers.Agent do
  alias Coflux.Orchestration

  def init(req, _opts) do
    qs = :cowboy_req.parse_qs(req)
    # TODO: validate
    project_id = get_query_param(qs, "project")
    environment = get_query_param(qs, "environment")
    session_id = get_query_param(qs, "session")

    {:cowboy_websocket, req, {project_id, environment, session_id}}
  end

  def websocket_init({project_id, environment, session_id}) do
    # TODO: authenticate
    # TODO: monitor server?
    session_id = if session_id, do: String.to_integer(session_id)

    case Orchestration.connect(project_id, environment, session_id, self()) do
      {:ok, session_id} ->
        {[session_message(session_id)],
         %{
           project_id: project_id,
           environment: environment,
           session_id: session_id,
           requests: %{}
         }}

      {:error, :no_session} ->
        {[{:close, 4001, "no_session"}], nil}
    end
  end

  def websocket_handle({:text, text}, state) do
    message = Jason.decode!(text)

    case message["request"] do
      "register" ->
        [repository, _version, targets] = message["params"]
        targets = parse_targets(targets)

        case Orchestration.register_targets(
               state.project_id,
               state.environment,
               state.session_id,
               repository,
               targets
             ) do
          :ok ->
            {[], state}
        end

      "schedule_task" ->
        [repository, target, arguments, parent_id] = message["params"]
        arguments = Enum.map(arguments, &parse_argument/1)

        # TODO: prevent scheduling unrecognised tasks?
        case Orchestration.schedule_task(
               state.project_id,
               state.environment,
               repository,
               target,
               arguments,
               parent_id
             ) do
          {:ok, run_id, _step_id, _execution_id} ->
            {[result_message(message["id"], run_id)], state}
        end

      "schedule_step" ->
        [repository, target, arguments, parent_id, cache_key] = message["params"]
        arguments = Enum.map(arguments, &parse_argument/1)

        case Orchestration.schedule_step(
               state.project_id,
               state.environment,
               repository,
               target,
               arguments,
               parent_id,
               cache_key
             ) do
          {:ok, _step_id, execution_id} ->
            {[result_message(message["id"], execution_id)], state}
        end

      "record_heartbeats" ->
        [executions] = message["params"]
        executions = Map.new(executions, fn {k, v} -> {String.to_integer(k), v} end)
        :ok = Orchestration.record_heartbeats(state.project_id, state.environment, executions)
        {[], state}

      "put_cursor" ->
        [execution_id, result] = message["params"]
        result = parse_result(result)

        :ok =
          Orchestration.record_cursor(
            state.project_id,
            state.environment,
            execution_id,
            result
          )

        {[], state}

      "put_result" ->
        [execution_id, result] = message["params"]
        result = parse_result(result)

        :ok =
          Orchestration.record_result(
            state.project_id,
            state.environment,
            execution_id,
            result
          )

        {[], state}

      "put_error" ->
        [execution_id, error, details] = message["params"]

        :ok =
          Orchestration.record_result(
            state.project_id,
            state.environment,
            execution_id,
            {:error, error, details}
          )

        {[], state}

      "get_result" ->
        [execution_id, from_execution_id] = message["params"]

        case Orchestration.get_result(
               state.project_id,
               state.environment,
               execution_id,
               from_execution_id,
               self()
             ) do
          {:ok, result} ->
            {[result_message(message["id"], compose_result(result))], state}

          {:wait, ref} ->
            state = put_in(state.requests[ref], message["id"])
            {[], state}
        end

      "log_message" ->
        # TODO
        # [execution_id, level, log_message] = message["params"]
        # Project.log_message(state.project_id, execution_id, level, log_message)
        {[], state}
    end
  end

  def websocket_handle(_data, state) do
    {[], state}
  end

  def websocket_info({:execute, execution_id, repository, target, arguments}, state) do
    arguments = Enum.map(arguments, &compose_argument/1)
    {[command_message("execute", [execution_id, repository, target, arguments])], state}
  end

  def websocket_info({:result, ref, result}, state) do
    {id, state} = pop_in(state.requests[ref])
    {[result_message(id, compose_result(result))], state}
  end

  def websocket_info({:abort, execution_id}, state) do
    {[command_message("abort", [execution_id])], state}
  end

  defp session_message(session_id) do
    {:text, Jason.encode!([0, session_id])}
  end

  defp command_message(command, params) do
    {:text, Jason.encode!([1, %{"command" => command, "params" => params}])}
  end

  defp result_message(id, result) do
    {:text, Jason.encode!([2, %{"id" => id, "result" => result}])}
  end

  defp get_query_param(qs, key) do
    case List.keyfind(qs, key, 0) do
      {^key, value} -> value
      nil -> nil
    end
  end

  defp parse_targets(targets) do
    Map.new(targets, fn {key, value} ->
      {key,
       %{
         type: parse_type(Map.fetch!(value, "type")),
         parameters: Enum.map(Map.fetch!(value, "parameters"), &parse_parameter/1)
       }}
    end)
  end

  defp parse_type(type) do
    case type do
      "task" -> :task
      "step" -> :step
      "sensor" -> :sensor
    end
  end

  defp parse_parameter(parameters) do
    {
      Map.fetch!(parameters, "name"),
      Map.get(parameters, "default"),
      Map.get(parameters, "annotation")
    }
  end

  defp parse_argument(argument) do
    case argument do
      ["raw", format, value] -> {:raw, format, value}
      ["blob", format, key] -> {:blob, format, key}
      ["reference", execution_id] -> {:reference, execution_id}
    end
  end

  defp compose_argument(result) do
    case result do
      {:raw, format, value} -> ["raw", format, value]
      {:blob, format, key} -> ["blob", format, key]
      {:reference, execution_id} -> ["reference", execution_id]
    end
  end

  defp parse_result(result) do
    case result do
      ["raw", format, value] -> {:raw, format, value}
      ["blob", format, key] -> {:blob, format, key}
      ["reference", execution_id] -> {:reference, execution_id}
    end
  end

  defp compose_result(result) do
    case result do
      {:raw, format, value} -> ["raw", format, value]
      {:blob, format, key} -> ["blob", format, key]
      {:reference, execution_id} -> ["reference", execution_id]
      {:error, error, _details} -> ["error", error]
      :abandoned -> ["abandoned"]
      :aborted -> ["aborted"]
    end
  end
end

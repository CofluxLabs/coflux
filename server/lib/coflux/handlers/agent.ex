defmodule Coflux.Handlers.Agent do
  alias Coflux.{Orchestration, Logging}

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

      "schedule" ->
        [
          repository,
          target,
          arguments,
          parent_id,
          execute_after,
          cache_key,
          deduplicate_key,
          retry_count,
          retry_delay_min,
          retry_delay_max
        ] = message["params"]

        arguments = Enum.map(arguments, &parse_argument/1)

        case Orchestration.schedule(
               state.project_id,
               state.environment,
               repository,
               target,
               arguments,
               parent_id: parent_id,
               cache_key: cache_key,
               retry_count: retry_count,
               retry_delay_min: retry_delay_min,
               retry_delay_max: retry_delay_max,
               deduplicate_key: deduplicate_key,
               execute_after: execute_after
             ) do
          {:ok, _run_id, _step_id, execution_id} ->
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

      "log_messages" ->
        messages =
          Enum.map(message["params"], fn [execution_id, timestamp, level, message] ->
            {execution_id, timestamp, parse_level(level), message}
          end)

        execution_ids = Enum.map(messages, fn {execution_id, _, _, _} -> execution_id end)
        run_ids = Orchestration.lookup_runs(state.project_id, state.environment, execution_ids)

        messages
        |> Enum.group_by(fn {execution_id, _, _, _} -> Map.fetch!(run_ids, execution_id) end)
        |> Enum.each(fn {run_id, messages} ->
          Logging.write(state.project_id, state.environment, run_id, messages)
        end)

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
      :cancelled -> ["cancelled"]
      :duplicated -> ["duplicated"]
    end
  end

  def parse_level(level) do
    case level do
      0 -> :stdout
      1 -> :stderr
      2 -> :debug
      3 -> :info
      4 -> :warning
      5 -> :error
    end
  end
end

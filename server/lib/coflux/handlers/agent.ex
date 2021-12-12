defmodule Coflux.Handlers.Agent do
  alias Coflux.Project

  def init(req, _opts) do
    bindings = :cowboy_req.bindings(req)
    {:cowboy_websocket, req, bindings[:project]}
  end

  def websocket_init(project_id) do
    # TODO: authenticate
    # TODO: monitor project server?
    {[], %{project_id: project_id, requests: %{}}}
  end

  def websocket_handle({:text, text}, state) do
    message = Jason.decode!(text)

    case message["method"] do
      "register" ->
        [repository, version, manifest] = message["params"]
        manifest = parse_manifest(manifest)

        case Project.register(state.project_id, repository, version, manifest, self()) do
          :ok ->
            {[], state}
        end

      "schedule_task" ->
        [repository, target, arguments, parent_id] = message["params"]
        arguments = Enum.map(arguments, &parse_argument/1)

        # TODO: prevent scheduling unrecognised tasks?
        case Project.schedule_task(state.project_id, repository, target, arguments,
               execution_id: parent_id
             ) do
          {:ok, run_id} ->
            {[result_message(message["id"], run_id)], state}
        end

      "schedule_step" ->
        [repository, target, arguments, parent_id, cache_key] = message["params"]
        arguments = Enum.map(arguments, &parse_argument/1)

        case Project.schedule_step(state.project_id, parent_id, repository, target, arguments,
               cache_key: cache_key
             ) do
          {:ok, execution_id} ->
            {[result_message(message["id"], execution_id)], state}
        end

      "record_heartbeats" ->
        [executions] = message["params"]
        Project.record_heartbeats(state.project_id, executions)
        {[], state}

      "put_cursor" ->
        [execution_id, type, value] = message["params"]
        cursor = parse_cursor(type, value)
        Project.put_cursor(state.project_id, execution_id, cursor)
        {[], state}

      "put_result" ->
        [execution_id, type, value] = message["params"]
        result = parse_result(type, value)
        :ok = Project.put_result(state.project_id, execution_id, result)
        {[], state}

      "put_error" ->
        [execution_id, error, details] = message["params"]
        :ok = Project.put_result(state.project_id, execution_id, {:failed, error, details})
        {[], state}

      "get_result" ->
        [execution_id, from_execution_id] = message["params"]

        case Project.get_result(state.project_id, execution_id, from_execution_id, self()) do
          {:ok, result} ->
            {[result_message(message["id"], compose_result(result))], state}

          {:wait, ref} ->
            state = put_in(state.requests[ref], message["id"])
            {[], state}
        end
    end
  end

  def websocket_handle(_data, state) do
    {[], state}
  end

  def websocket_info({:execute, execution_id, target, arguments}, state) do
    arguments = Enum.map(arguments, &compose_argument/1)
    {[notify_message("execute", [execution_id, target, arguments])], state}
  end

  def websocket_info({:result, ref, result}, state) do
    {id, state} = pop_in(state.requests[ref])
    {[result_message(id, compose_result(result))], state}
  end

  def websocket_info({:abort, execution_id}, state) do
    {[notify_message("abort", [execution_id])], state}
  end

  def websocket_info(_info, state) do
    {[], state}
  end

  defp notify_message(method, params) do
    {:text, Jason.encode!(%{"method" => method, "params" => params})}
  end

  defp result_message(id, result) do
    {:text, Jason.encode!(%{"id" => id, "result" => result})}
  end

  defp parse_manifest(manifest) do
    Map.new(manifest, fn {key, value} ->
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
    %{
      name: Map.fetch!(parameters, "name"),
      annotation: Map.get(parameters, "annotation"),
      default: Map.get(parameters, "default")
    }
  end

  defp parse_argument(argument) do
    case argument do
      ["json", value] -> {:json, value}
      ["blob", key] -> {:blob, key}
      ["result", execution_id] -> {:result, execution_id}
    end
  end

  def compose_argument(result) do
    case result do
      {:json, value} -> ["json", value]
      {:blob, key} -> ["blob", key]
      {:result, execution_id} -> ["result", execution_id]
    end
  end

  def parse_result(type, value) do
    case type do
      "json" -> {:json, value}
      "blob" -> {:blob, value}
      "result" when is_binary(value) -> {:result, value}
    end
  end

  def parse_cursor(type, value) do
    case type do
      "json" -> {:json, value}
      "blob" -> {:blob, value}
    end
  end

  def compose_result(result) do
    case result do
      {:json, value} -> ["json", value]
      {:blob, key} -> ["blob", key]
      {:result, execution_id} -> ["result", execution_id]
      {:failed, error, extra} -> ["failed", error, extra]
    end
  end
end

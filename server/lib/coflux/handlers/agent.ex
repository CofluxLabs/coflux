defmodule Coflux.Handlers.Agent do
  alias Coflux.{Orchestration, Observation, Projects}

  def init(req, _opts) do
    qs = :cowboy_req.parse_qs(req)
    # TODO: validate
    project_id = get_query_param(qs, "project")
    environment = get_query_param(qs, "environment")
    session_id = get_query_param(qs, "session")
    concurrency = get_query_param(qs, "concurrency", &String.to_integer/1) || 0

    {:cowboy_websocket, req, {project_id, environment, session_id, concurrency}}
  end

  def websocket_init({project_id, environment, session_id, concurrency}) do
    case Projects.get_project_by_id(Coflux.ProjectsServer, project_id) do
      {:ok, project} ->
        # TODO: authenticate
        if Enum.member?(project.environments, environment) do
          # TODO: monitor server?
          case Orchestration.connect(project_id, environment, session_id, concurrency, self()) do
            {:ok, session_id, executions} ->
              {[session_message(session_id)],
               %{
                 project_id: project_id,
                 environment: environment,
                 session_id: session_id,
                 executions: executions
               }}

            {:error, :no_session} ->
              {[{:close, 4000, "session_invalid"}], nil}
          end
        else
          {[{:close, 4000, "environment_not_found"}], nil}
        end

      :error ->
        {[{:close, 4000, "project_not_found"}], nil}
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
          wait_for,
          cache_key,
          cache_max_age,
          defer_key,
          memo_key,
          retry_count,
          retry_delay_min,
          retry_delay_max
        ] = message["params"]

        arguments = Enum.map(arguments, &parse_value/1)

        if is_nil(parent_id) || is_recognised_execution?(parent_id, state) do
          case Orchestration.schedule(
                 state.project_id,
                 state.environment,
                 repository,
                 target,
                 arguments,
                 parent_id: parent_id,
                 execute_after: execute_after,
                 wait_for: wait_for,
                 cache_key: cache_key,
                 cache_max_age: cache_max_age,
                 retry_count: retry_count,
                 retry_delay_min: retry_delay_min,
                 retry_delay_max: retry_delay_max,
                 defer_key: defer_key,
                 memo_key: memo_key
               ) do
            {:ok, _run_id, _step_id, execution_id} ->
              {[success_message(message["id"], execution_id)], state}

            {:error, error} ->
              {[error_message(message["id"], error)], state}
          end
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "record_heartbeats" ->
        [executions] = message["params"]
        executions = Map.new(executions, fn {k, v} -> {String.to_integer(k), v} end)

        if Enum.all?(Map.keys(executions), &is_recognised_execution?(&1, state)) do
          :ok =
            Orchestration.record_heartbeats(
              state.project_id,
              state.environment,
              executions,
              state.session_id
            )

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "record_checkpoint" ->
        [execution_id, arguments] = message["params"]

        if is_recognised_execution?(execution_id, state) do
          arguments = Enum.map(arguments, &parse_value/1)

          :ok =
            Orchestration.record_checkpoint(
              state.project_id,
              state.environment,
              execution_id,
              arguments
            )

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "notify_terminated" ->
        [execution_ids] = message["params"]

        # TODO: just ignore?
        if Enum.all?(execution_ids, &is_recognised_execution?(&1, state)) do
          :ok =
            Orchestration.notify_terminated(state.project_id, state.environment, execution_ids)

          state = Map.update!(state, :executions, &Map.drop(&1, execution_ids))

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "put_result" ->
        [execution_id, value] = message["params"]

        if is_recognised_execution?(execution_id, state) do
          :ok =
            Orchestration.record_result(
              state.project_id,
              state.environment,
              execution_id,
              {:value, parse_value(value)}
            )

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "put_error" ->
        [execution_id, error] = message["params"]

        if is_recognised_execution?(execution_id, state) do
          {type, message, frames} = parse_error(error)

          :ok =
            Orchestration.record_result(
              state.project_id,
              state.environment,
              execution_id,
              {:error, type, message, frames}
            )

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "get_result" ->
        [execution_id, from_execution_id] = message["params"]

        if is_recognised_execution?(from_execution_id, state) do
          case Orchestration.get_result(
                 state.project_id,
                 state.environment,
                 execution_id,
                 from_execution_id,
                 state.session_id,
                 message["id"]
               ) do
            {:ok, result} ->
              {[success_message(message["id"], compose_result(result))], state}

            :wait ->
              {[], state}
          end
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "put_asset" ->
        [execution_id, type, path, blob_key, metadata] = message["params"]

        if is_recognised_execution?(execution_id, state) do
          {:ok, asset_id} =
            Orchestration.put_asset(
              state.project_id,
              state.environment,
              execution_id,
              type,
              path,
              blob_key,
              metadata
            )

          {[success_message(message["id"], asset_id)], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "get_asset" ->
        [asset_id, from_execution_id] = message["params"]

        if is_recognised_execution?(from_execution_id, state) do
          case Orchestration.get_asset(
                 state.project_id,
                 state.environment,
                 asset_id,
                 from_execution_id
               ) do
            {:ok, asset_type, path, blob_key} ->
              {[success_message(message["id"], [asset_type, path, blob_key])], state}

            {:error, error} ->
              {[error_message(message["id"], error)], state}
          end
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end

      "log_messages" ->
        messages =
          Enum.map(message["params"], fn [execution_id, timestamp, level, template, labels] ->
            {execution_id, timestamp, parse_level(level), template, labels}
          end)

        execution_ids = Enum.map(messages, &elem(&1, 0))

        if Enum.all?(execution_ids, &is_recognised_execution?(&1, state)) do
          messages
          |> Enum.group_by(&Map.fetch!(state.executions, elem(&1, 0)))
          |> Enum.each(fn {run_id, messages} ->
            Observation.write(state.project_id, state.environment, run_id, messages)
          end)

          {[], state}
        else
          {[{:close, 4000, "execution_invalid"}], nil}
        end
    end
  end

  def websocket_handle(_data, state) do
    {[], state}
  end

  def websocket_info({:execute, execution_id, repository, target, arguments, run_id}, state) do
    arguments = Enum.map(arguments, &compose_value/1)
    state = put_in(state.executions[execution_id], run_id)
    {[command_message("execute", [execution_id, repository, target, arguments])], state}
  end

  def websocket_info({:result, request_id, result}, state) do
    {[success_message(request_id, compose_result(result))], state}
  end

  def websocket_info({:abort, execution_id}, state) do
    {[command_message("abort", [execution_id])], state}
  end

  defp is_recognised_execution?(execution_id, state) do
    Map.has_key?(state.executions, execution_id)
  end

  defp session_message(session_id) do
    {:text, Jason.encode!([0, session_id])}
  end

  defp command_message(command, params) do
    {:text, Jason.encode!([1, %{"command" => command, "params" => params}])}
  end

  defp success_message(id, result) do
    {:text, Jason.encode!([2, id, result])}
  end

  defp error_message(id, error) do
    {:text, Jason.encode!([3, id, error])}
  end

  defp get_query_param(qs, key, fun \\ nil) do
    case List.keyfind(qs, key, 0) do
      {^key, value} ->
        if fun do
          try do
            fun.(value)
          rescue
            ArgumentError ->
              nil
          end
        else
          value
        end

      nil ->
        nil
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
      "workflow" -> :workflow
      "task" -> :task
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

  defp parse_frames(frames) do
    Enum.map(frames, fn [file, line, name, code] ->
      {file, line, name, code}
    end)
  end

  defp parse_error(error) do
    case error do
      nil ->
        nil

      [type, message, frames] ->
        {type, message, parse_frames(frames)}
    end
  end

  defp parse_placeholders(placeholders) do
    Map.new(placeholders, fn {placeholder, [execution_id, asset_id]} ->
      {String.to_integer(placeholder), {execution_id, asset_id}}
    end)
  end

  defp parse_value(value) do
    case value do
      ["raw", content, format, placeholders] ->
        {{:raw, content}, format, parse_placeholders(placeholders)}

      ["blob", blob_key, metadata, format, placeholders] ->
        {{:blob, blob_key, metadata}, format, parse_placeholders(placeholders)}
    end
  end

  defp compose_placeholders(placeholders) do
    Map.new(placeholders, fn {placeholder, {execution_id, asset_id}} ->
      {Integer.to_string(placeholder), [execution_id, asset_id]}
    end)
  end

  defp compose_value(value) do
    case value do
      {{:raw, content}, format, placeholders} ->
        ["raw", content, format, compose_placeholders(placeholders)]

      {{:blob, blob_key, metadata}, format, placeholders} ->
        ["blob", blob_key, metadata, format, compose_placeholders(placeholders)]
    end
  end

  defp compose_result(result) do
    case result do
      {:error, type, message, _frames, nil} -> ["error", type, message]
      {:value, value} -> ["value", compose_value(value)]
      {:abandoned, nil} -> ["abandoned"]
      :cancelled -> ["cancelled"]
    end
  end

  defp parse_level(level) do
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

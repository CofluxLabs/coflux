defmodule Coflux.Handlers.Events do
  alias Coflux.Project

  def init(req, _opts) do
    bindings = :cowboy_req.bindings(req)
    {:cowboy_websocket, req, bindings[:project]}
  end

  def websocket_init(project_id) do
    # TODO: authenticate
    # TODO: monitor project server?
    {[],
     %{
       project_id: project_id,
       subscription_ids: %{},
       subscription_refs: %{}
     }}
  end

  def websocket_handle({:text, text}, state) do
    message = Jason.decode!(text)

    case message["method"] do
      "subscribe" ->
        [topic, arguments, subscription_id] = message["params"]

        case Project.subscribe(state.project_id, topic, arguments, self()) do
          {:ok, ref, value} ->
            # TODO: validate subscription id (check numeric and unused)

            state =
              state
              |> put_in([:subscription_ids, ref], subscription_id)
              |> put_in([:subscription_refs, subscription_id], {topic, arguments, ref})

            {[result_message(message["id"], value)], state}

          {:error, :not_found} ->
            {[result_message(message["id"], nil)], state}
        end

      "unsubscribe" ->
        [subscription_id] = message["params"]

        case Map.fetch(state.subscription_refs, subscription_id) do
          {:ok, {topic, arguments, ref}} ->
            case Project.unsubscribe(state.project_id, topic, arguments, ref) do
              :ok ->
                state =
                  state
                  |> Map.update!(:subscription_ids, &Map.delete(&1, ref))
                  |> Map.update!(:subscription_refs, &Map.delete(&1, subscription_id))

                {[], state}
            end

          :error ->
            # TODO: ?
            {[], state}
        end

      "start_run" ->
        [repository, target, environment_name, arguments] = message["params"]
        arguments = Enum.map(arguments, &parse_argument/1)

        # TODO: prevent scheduling unrecognised tasks?
        with {:ok, environment} <-
               Project.get_environment_by_name(state.project_id, environment_name) do
          case Project.schedule_task(
                 state.project_id,
                 environment.id,
                 repository,
                 target,
                 arguments
               ) do
            {:ok, run_id} ->
              {[result_message(message["id"], run_id)], state}
          end
        end

      "rerun_step" ->
        [run_id, step_id, environment_name] = message["params"]

        with {:ok, environment} <-
               Project.get_environment_by_name(state.project_id, environment_name) do
          case Project.rerun_step(state.project_id, run_id, step_id,
                 environment_id: environment.id
               ) do
            {:ok, attempt} ->
              {[result_message(message["id"], attempt)], state}
          end
        end

      "activate_sensor" ->
        [repository, target, environment_name] = message["params"]

        with {:ok, environment} <-
               Project.get_environment_by_name(state.project_id, environment_name) do
          case Project.activate_sensor(state.project_id, environment.id, repository, target) do
            {:ok, activation_id} ->
              {[result_message(message["id"], activation_id)], state}
          end
        end

      "deactivate_sensor" ->
        [activation_id] = message["params"]
        :ok = Project.deactivate_sensor(state.project_id, activation_id)
        {[result_message(message["id"], true)], state}
    end
  end

  def websocket_handle(_data, state) do
    {[], state}
  end

  def websocket_info({:update, ref, path, value}, state) do
    subscription_id = Map.fetch!(state.subscription_ids, ref)
    message = notify_message("update", [subscription_id, path, value])
    {[message], state}
  end

  def websocket_info(_info, state) do
    {[], state}
  end

  defp notify_message(method, params) do
    {:text, Jason.encode!(%{"method" => method, "params" => camelize(params)})}
  end

  defp result_message(id, result) do
    {:text, Jason.encode!(%{"id" => id, "result" => camelize(result)})}
  end

  defp parse_argument(argument) do
    case argument do
      ["json", value] -> {:json, value}
      ["blob", key] -> {:blob, key}
      ["result", execution_id] -> {:result, execution_id}
    end
  end

  defp camelize(value) do
    cond do
      is_map(value) and !is_struct(value) ->
        Map.new(value, fn {k, v} -> {camelize(k), camelize(v)} end)

      is_list(value) ->
        Enum.map(value, &camelize/1)

      is_atom(value) && value not in [true, false, nil] ->
        Inflex.camelize(value, :lower)

      true ->
        value
    end
  end
end

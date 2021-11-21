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
        [topic, subscription_id] = message["params"]

        case Project.subscribe(state.project_id, topic, self()) do
          {:ok, ref, value} ->
            # TODO: validate subscription id (check numeric and unused)

            state =
              state
              |> put_in([:subscription_ids, ref], subscription_id)
              |> put_in([:subscription_refs, subscription_id], ref)

            {[result_message(message["id"], value)], state}
        end

      "unsubscribe" ->
        [subscription_id] = message["params"]
        ref = Map.fetch!(state.subscription_refs, subscription_id)

        case Project.unsubscribe(state.project_id, ref) do
          :ok ->
            state =
              state
              |> Map.update!(:subscription_ids, &Map.delete(&1, ref))
              |> Map.update!(:subscription_refs, &Map.delete(&1, subscription_id))

            {[], state}
        end

      "startRun" ->
        # TODO
        {[], state}
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

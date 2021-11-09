defmodule Coflux.Handlers.ExecutionResult do
  import Coflux.Handlers.Utils
  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    handle(req, :cowboy_req.method(req), bindings[:project], bindings[:execution], opts)
  end

  defp handle(req, "GET", project_id, execution_id, opts) do
    case Project.get_result(project_id, execution_id) do
      {:ok, result} ->
        response =
          case result do
            {:completed, value} ->
              %{"status" => "completed", "value" => compose_result(value)}

            {:failed, message, details} ->
              %{"status" => "failed", "message" => message, "details" => details}
          end

        req = json_response(req, response)
        {:ok, req, opts}
    end
  end

  defp handle(req, "PUT", project_id, execution_id, opts) do
    case read_json_body(req) do
      {:ok, data, req} ->
        result =
          case Map.fetch!(data, "status") do
            "completed" ->
              {:completed, parse_result(Map.fetch!(data, "value"))}

            "failed" ->
              {:failed, Map.fetch!(data, "message"), Map.get(data, "details")}
          end

        case Project.put_result(project_id, execution_id, result) do
          :ok ->
            req = :cowboy_req.reply(204, req)
            {:ok, req, opts}
        end
    end
  end
end

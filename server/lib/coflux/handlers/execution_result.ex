defmodule Coflux.Handlers.ExecutionResult do
  import Coflux.Handlers.Utils
  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    handle(req, :cowboy_req.method(req), bindings[:project], bindings[:execution], opts)
  end

  defp handle(req, "GET", project_id, execution_id, opts) do
    case Project.get_result(project_id, execution_id) do
      nil ->
        req = :cowboy_req.reply(202, req)
        {:ok, req, opts}

      result ->
        req = json_response(req, compose_result(result))
        {:ok, req, opts}
    end
  end

  defp handle(req, "PUT", project_id, execution_id, opts) do
    case read_json_body(req) do
      {:ok, data, req} ->
        Project.put_result(project_id, execution_id, parse_result(data))
        req = :cowboy_req.reply(204, req)
        {:ok, req, opts}
    end
  end

  def compose_result(result) do
    case result do
      {:raw, value} -> ["raw", value]
      {:result, execution_id} -> ["result", execution_id]
      {:failed, error, extra} -> ["failed", error, extra]
    end
  end

  def parse_result(data) do
    case data do
      ["raw", value] -> {:raw, value}
      ["result", execution_id] when is_binary(execution_id) -> {:result, execution_id}
      ["failed", error, extra] when is_binary(error) and is_map(extra) -> {:failed, error, extra}
    end
  end
end

defmodule Coflux.Handlers.ExecutionChildren do
  import Coflux.Handlers.Utils
  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    handle(req, :cowboy_req.method(req), bindings[:project], bindings[:execution], opts)
  end

  defp handle(req, "POST", project_id, execution_id, opts) do
    case read_json_body(req) do
      {:ok, data, req} ->
        target = Map.fetch!(data, "target")
        arguments = data |> Map.fetch!("arguments") |> Enum.map(&parse_result/1)

        case Project.schedule(project_id, target, arguments, execution_id) do
          {:ok, new_execution_id} ->
            req = json_response(req, %{"executionId" => new_execution_id})
            {:ok, req, opts}
        end
    end
  end
end

defmodule Coflux.Handlers.Agents do
  import Coflux.Handlers.Utils
  alias Coflux.Project

  @tick_interval_ms 1000
  @timeout_ms 30_000

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)
    handle(req, :cowboy_req.method(req), bindings[:project], opts)
  end

  defp handle(req, "POST", project_id, opts) do
    case read_json_body(req) do
      {:ok, data, req} ->
        case Project.register(
               project_id,
               data["repository"],
               data["version"],
               parse_targets(data["targets"]),
               self()
             ) do
          :ok ->
            req = :cowboy_req.stream_reply(200, %{"content-type" => "application/x-ndjson"}, req)
            Process.send_after(self(), :tick, @tick_interval_ms)
            Process.send_after(self(), :timeout, @timeout_ms)
            {:cowboy_loop, req, opts}
        end
    end
  end

  def info(:tick, req, state) do
    :cowboy_req.stream_body("\n", :nofin, req)
    Process.send_after(self(), :tick, @tick_interval_ms)
    {:ok, req, state}
  end

  def info(:timeout, req, state) do
    {:stop, req, state}
  end

  def info({:execute, execution_id, target, arguments}, req, state) do
    send_command(req, "execute", %{
      "executionId" => execution_id,
      "target" => target,
      "arguments" => Enum.map(arguments, &compose_argument/1)
    })

    {:ok, req, state}
  end

  defp send_command(req, command, arguments) do
    data = Jason.encode!([command, arguments])
    :cowboy_req.stream_body("#{data}\n", :nofin, req)
  end

  defp parse_targets(targets) do
    Map.new(targets, fn {key, value} -> {key, %{type: parse_type(Map.get(value, "type"))}} end)
  end

  defp parse_type(type) do
    case type do
      "task" -> :task
      "step" -> :step
    end
  end

  def compose_argument(result) do
    case result do
      {:raw, value} -> ["raw", value]
      {:result, execution_id} -> ["result", execution_id]
    end
  end
end

defmodule Coflux.Handlers.Agents do
  import Coflux.Handlers.Utils

  alias Coflux.Project

  def init(req, opts) do
    bindings = :cowboy_req.bindings(req)

    req
    |> set_cors_headers()
    |> handle(:cowboy_req.method(req), bindings[:project], bindings[:agent], opts)
  end

  defp handle(req, "GET", project_id, nil, opts) do
    case Project.get_agents(project_id) do
      {:ok, agents} ->
        result =
          Enum.map(agents, fn {pid, targets} ->
            %{
              "id" => :erlang.list_to_binary(:erlang.pid_to_list(pid)),
              "targets" =>
                Enum.map(targets, fn {{repository, target}, version} ->
                  %{
                    "repository" => repository,
                    "target" => target,
                    "version" => version
                  }
                end)
            }
          end)

        req = json_response(req, result)
        {:ok, req, opts}
    end
  end
end

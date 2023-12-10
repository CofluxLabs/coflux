defmodule Coflux.Application do
  use Application

  alias Coflux.{Projects, Orchestration, Logging, Topics}

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "7777"))

    children = [
      {Projects, name: Coflux.ProjectsServer},
      Orchestration.Supervisor,
      Logging.Supervisor,
      {Topical, name: Coflux.TopicalRegistry, topics: topics()},
      {Coflux.Web, port: port}
    ]

    opts = [strategy: :one_for_one, name: Coflux.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      IO.puts("Server started. Running on port #{port}.")
      {:ok, pid}
    end
  end

  defp topics() do
    [
      Topics.Agents,
      Topics.Projects,
      Topics.Repositories,
      Topics.Run,
      Topics.Sensor,
      Topics.Task,
      Topics.Logs
    ]
  end
end

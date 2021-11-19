defmodule Coflux.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "7070"))
    project_ids = String.split(System.get_env("PROJECT_IDS", ""), ",")

    children = [
      Coflux.Repo.Projects,
      {Coflux.Listener, repo: Coflux.Repo.Projects, name: Coflux.ProjectsListener},
      {Coflux.Project.Orchestrator.Supervisor, project_ids: project_ids},
      Coflux.Project.Observer.Supervisor,
      {Coflux.Api, port: port}
    ]

    with {:ok, pid} <-
           Supervisor.start_link(
             children,
             strategy: :one_for_one,
             name: Coflux.Supervisor
           ) do
      IO.puts("Server started. API running on port #{port}.")
      {:ok, pid}
    end
  end
end

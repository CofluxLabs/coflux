defmodule Coflux.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "7070"))
    project_ids = String.split(System.get_env("PROJECT_IDS", ""), ",")

    Supervisor.start_link(
      [
        Coflux.Repo.Projects,
        {Coflux.Listener, repo: Coflux.Repo.Projects, name: Coflux.ProjectsListener},
        {Coflux.Project.Supervisor, project_ids: project_ids},
        {Coflux.Api, port: port}
      ],
      strategy: :one_for_one,
      name: Coflux.Supervisor
    )
  end
end

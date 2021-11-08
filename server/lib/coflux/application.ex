defmodule Coflux.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "7070"))

    Supervisor.start_link(
      [
        {Registry, name: Coflux.ProjectsRegistry, keys: :unique},
        {DynamicSupervisor, name: Coflux.ProjectsSupervisor, strategy: :one_for_one},
        {Coflux.Api, port: port}
      ],
      strategy: :one_for_one,
      name: Coflux.Supervisor
    )
  end
end

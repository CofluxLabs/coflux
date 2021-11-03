defmodule Coflux.Application do
  use Application

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "4000"))

    Supervisor.start_link(
      [
        {Coflux.Api, port: port}
      ],
      strategy: :one_for_one,
      name: Coflux.Supervisor
    )
  end
end

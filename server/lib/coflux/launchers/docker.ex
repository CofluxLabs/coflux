defmodule Coflux.DockerLauncher do
  def launch(project_id, environment_name, launch_id, config \\ %{}) do
    # TODO: option to configure docker host?
    # TODO: option to configure coflux host/port?
    # TODO: option to pass "--rm"?
    System.cmd("docker", [
      "run",
      "--detach",
      "--add-host=host.docker.internal:host-gateway",
      Map.fetch!(config, :image),
      "--host=host.docker.internal:7777",
      "--environment=#{environment_name}",
      "--project=#{project_id}",
      "--launch=#{launch_id}"
    ])
  end
end

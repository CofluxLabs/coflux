defmodule Coflux.Application do
  use Application

  alias Coflux.{Projects, Orchestration, Logging, Topics}

  @mix_env Mix.env()

  @impl true
  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "7777"))

    children =
      [
        {Projects, name: Coflux.ProjectsServer},
        Orchestration.Supervisor,
        Logging.Supervisor,
        {Topical, name: Coflux.TopicalRegistry, topics: topics()},
        {Coflux.Web, port: port},
        is_env(:dev) && {Task, &build_assets/0}
      ]
      |> Enum.filter(& &1)

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
      Topics.Target,
      Topics.Logs
    ]
  end

  defp is_env(env) do
    @mix_env == env
  end

  defp build_assets() do
    npm(["install"])
    npm(["run", "build", "--", "--watch"])
  end

  defp npm(args) do
    case System.cmd("npm", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> raise "npm command fiiled (#{code}):\n#{output}"
    end
  end
end

defmodule Coflux do
  alias Coflux.Orchestration

  def execute(project_id, environment, repository, target, arguments \\ [], timeout \\ :infinity) do
    case Orchestration.schedule(project_id, environment, repository, target, arguments) do
      {:ok, _, _, execution_id} ->
        case Orchestration.get_result(project_id, environment, execution_id, self()) do
          {:ok, result} ->
            {:ok, result}

          {:wait, ref} ->
            receive do
              {:result, ^ref, result} ->
                {:ok, result}
            after
              timeout ->
                {:error, :timeout}
            end
        end
    end
  end

  def inspect(project_id, environment \\ "development") do
    {:ok, pid} = Orchestration.Supervisor.get_server(project_id, environment)
    :sys.get_state(pid)
  end
end

defmodule Coflux do
  alias Coflux.Orchestration

  def execute(project_id, environment, repository, target, arguments \\ [], timeout \\ :infinity) do
    case Orchestration.schedule_task(project_id, environment, repository, target, arguments) do
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
end

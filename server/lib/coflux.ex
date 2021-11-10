defmodule Coflux do
  alias Coflux.Project

  def execute(project_id, repository, target, arguments \\ [], timeout \\ 5000) do
    project_id
    |> Project.list_tasks()
    |> Enum.find(&(&1.repository == repository && &1.target == target))
    |> case do
      nil ->
        {:error, :not_registered}

      task ->
        case Project.schedule_task(project_id, task.id, arguments) do
          {:ok, execution_id} ->
            case Project.get_result(project_id, execution_id, self()) do
              {:ok, result} ->
                handle_result(result)

              {:wait, ref} ->
                receive do
                  {:result, ^ref, result} ->
                    handle_result(result)
                after
                  timeout ->
                    {:error, :timeout}
                end
            end
        end
    end
  end

  defp handle_result(result) do
    case result do
      {:raw, value} -> {:ok, value}
      {:failed, message, _details} -> {:error, message}
    end
  end
end

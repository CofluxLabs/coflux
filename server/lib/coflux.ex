defmodule Coflux do
  alias Coflux.Project

  def execute(project_id, repository, target, arguments \\ [], opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)

    project_id
    |> Project.list_tasks()
    |> Enum.find(&(&1.repository == repository && &1.target == target))
    |> case do
      nil ->
        {:error, :not_registered}

      task ->
        case Project.schedule_task(project_id, task.id, arguments, opts) do
          {:ok, _run_id, execution_id} ->
            case Project.get_result(project_id, execution_id, self()) do
              {:ok, result} ->
                handle_result(result, project_id)

              {:wait, ref} ->
                receive do
                  {:result, ^ref, result} ->
                    handle_result(result, project_id)
                after
                  timeout ->
                    {:error, :timeout}
                end
            end
        end
    end
  end

  defp handle_result(result, project_id) do
    case result do
      {:json, value} -> {:ok, value}
      {:blob, key} -> Project.get_blob(project_id, key)
      {:failed, message, _details} -> {:error, message}
    end
  end
end

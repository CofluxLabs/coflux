defmodule Coflux.Project.Observer.Topics.Task do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Manifest, Models.Step]

  def load(project_id, [repository, target]) do
    with {:ok, manifest} <- Store.get_manifest(project_id, repository),
         {:ok, runs} <- Store.list_task_runs(project_id, repository, target) do
      case Map.fetch(manifest.tasks, target) do
        {:ok, parameters} ->
          runs =
            Map.new(runs, fn run ->
              {run.id, Map.take(run, [:id, :tags, :created_at])}
            end)

          task = %{
            repository: repository,
            version: manifest.version,
            target: target,
            parameters: parameters,
            runs: runs
          }

          {:ok, task, %{repository: repository, target: target}}

        :error ->
          {:error, :not_found}
      end
    end
  end

  def handle_insert(%Models.Manifest{} = manifest, _value, state) do
    if manifest.repository == state.repository && Map.has_key?(manifest.tasks, state.target) do
      case Map.fetch(manifest.tasks, state.target) do
        {:ok, parameters} ->
          {:ok, [{[:parameters], parameters}, {[:version], manifest.version}], state}

        :error ->
          # TODO: remove task?
          {:ok, [], state}
      end
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.Step{} = step, _value, state) do
    if step.repository == state.repository && step.target == state.target &&
         is_nil(step.parent_attempt) do
      {:ok, [{[:runs, step.run_id], %{id: step.run_id, created_at: step.created_at}}], state}
    else
      {:ok, [], state}
    end
  end
end

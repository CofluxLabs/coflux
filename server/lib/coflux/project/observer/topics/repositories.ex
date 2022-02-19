defmodule Coflux.Project.Observer.Topics.Repositories do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Manifest]

  def load(project_id, []) do
    case Store.list_repositories(project_id) do
      {:ok, repositories} ->
        {:ok, repositories, nil}
    end
  end

  def handle_insert(%Models.Manifest{} = manifest, _value, state) do
    {:ok, [{[manifest.repository], Map.take(manifest, [:version, :tasks, :sensors])}], state}
  end
end

defmodule Coflux.Project.Observer.Topics.Repositories do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Environment, Models.SessionManifest]

  def load(project_id, [environment_name]) do
    case Store.get_environment_by_name(project_id, environment_name) do
      {:ok, environment} ->
        load_repositories(project_id, environment)

      :error ->
        {:ok, %{}, %{project_id: project_id, environment_name: environment_name}}
    end
  end

  def handle_insert(%Models.Environment{} = environment, _value, state) do
    if Map.has_key?(state, :environment_name) && environment.name == state.environment_name do
      with {:ok, repositories, state} <- load_repositories(state.project_id, environment) do
        {:ok, [{[], repositories}], state}
      end
    else
      {:ok, [], state}
    end
  end

  def handle_insert(%Models.SessionManifest{} = session_manifest, _value, state) do
    with {:ok, session} <- Store.get_session(state.project_id, session_manifest.session_id) do
      if session.environment_id == state.environment_id do
        with {:ok, manifest} <- Store.get_manifest(state.project_id, session_manifest.manifest_id) do
          {:ok, [{[manifest.repository], get_value(manifest, session_manifest)}], state}
        end
      else
        {:ok, [], state}
      end
    end
  end

  defp load_repositories(project_id, environment) do
    with {:ok, manifests} <- Store.list_manifests(project_id, environment.id) do
      repositories =
        Map.new(manifests, fn {manifest, session_manifest} ->
          {manifest.repository, get_value(manifest, session_manifest)}
        end)

      {:ok, repositories, %{project_id: project_id, environment_id: environment.id}}
    end
  end

  defp get_value(manifest, session_manifest) do
    manifest
    |> Map.take([:repository, :version, :tasks, :sensors])
    |> Map.put(:active_at, session_manifest.created_at)
  end
end

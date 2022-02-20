defmodule Coflux.Project.Observer.Topics.Repositories do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.SessionManifest]

  def load(project_id, [environment_name]) do
    with {:ok, environment} <- Store.get_environment_by_name(project_id, environment_name),
         {:ok, manifests} <- Store.list_manifests(project_id, environment.id) do
      repositories =
        Map.new(manifests, fn {manifest, session_manifest} ->
          {manifest.repository, get_value(manifest, session_manifest)}
        end)

      {:ok, repositories, %{project_id: project_id, environment_id: environment.id}}
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

  defp get_value(manifest, session_manifest) do
    manifest
    |> Map.take([:repository, :version, :tasks, :sensors])
    |> Map.put(:active_at, session_manifest.created_at)
  end
end

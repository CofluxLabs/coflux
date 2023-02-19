defmodule Coflux.Project.Topics.Repositories do
  use Topical.Topic, route: "projects/:project_id/environments/:environment_name/repositories"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)
    environment_name = Keyword.fetch!(params, :environment_name)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.Environment, Models.SessionManifest]
      )

    case Store.get_environment_by_name(project_id, environment_name) do
      {:ok, environment} ->
        {:ok, repositories} = load_repositories(project_id, environment)
        {:ok, Topic.new(repositories, %{project_id: project_id, environment_id: environment.id})}

      :error ->
        {:ok, Topic.new(%{}, %{project_id: project_id, environment_name: environment_name})}
    end
  end

  def handle_info({:insert, _ref, %Models.Environment{} = environment}, topic) do
    if Map.has_key?(topic.state, :environment_name) && environment.name == topic.state.environment_name do
      with {:ok, repositories} <- load_repositories(topic.state.project_id, environment) do
        {:ok, Topic.set(topic, [], repositories)}
      end
    else
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.SessionManifest{} = session_manifest}, topic) do
    with {:ok, session} <- Store.get_session(topic.state.project_id, session_manifest.session_id) do
      if session.environment_id == topic.state.environment_id do
        with {:ok, manifest} <- Store.get_manifest(topic.state.project_id, session_manifest.manifest_id) do
          {:ok, Topic.set(topic, [manifest.repository], get_value(manifest, session_manifest))}
        end
      else
        {:ok, topic}
      end
    end
  end

  defp load_repositories(project_id, environment) do
    with {:ok, manifests} <- Store.list_manifests(project_id, environment.id) do
      repositories =
        Map.new(manifests, fn {manifest, session_manifest} ->
          {manifest.repository, get_value(manifest, session_manifest)}
        end)

      {:ok, repositories}
    end
  end

  defp get_value(manifest, session_manifest) do
    manifest
    |> Map.take([:repository, :version, :tasks, :sensors])
    |> Map.put(:activeAt, session_manifest.created_at)
  end
end

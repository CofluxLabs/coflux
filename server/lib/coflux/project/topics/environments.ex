defmodule Coflux.Project.Topics.Environments do
  use Topical.Topic, route: "projects/:project_id/environments"

  alias Coflux.Project.Store
  alias Coflux.Project.Models
  alias Coflux.Listener

  def init(params) do
    project_id = Keyword.fetch!(params, :project_id)

    :ok =
      Listener.subscribe(
        Coflux.ProjectsListener,
        project_id,
        self(),
        [Models.Environment]
      )

    with {:ok, environments} <- Store.list_environments(project_id) do
      value =
        Map.new(environments, fn environment ->
          {environment.id, Map.take(environment, [:id, :name])}
        end)

      topic = Topic.new(value, %{project_id: project_id})
      {:ok, topic}
    end
  end

  def handle_info({:insert, _ref, %Models.Environment{} = environment}, topic) do
    topic = Topic.set(topic, [environment.id], Map.take(environment, [:id, :name]))
    {:ok, topic}
  end
end

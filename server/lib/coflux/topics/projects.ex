defmodule Coflux.Topics.Projects do
  alias Coflux.Projects

  use Topical.Topic, route: ["projects"]

  @server Coflux.ProjectsServer

  def init(_params) do
    {ref, projects} = Projects.subscribe(@server, self())
    {:ok, Topic.new(projects, %{ref: ref})}
  end

  def handle_info({:project, _ref, project_id, project}, topic) do
    topic = Topic.set(topic, [project_id], project)
    {:ok, topic}
  end
end

defmodule Coflux.Topics.Projects do
  alias Coflux.{Projects, Orchestration}

  use Topical.Topic, route: ["projects"]

  @server Coflux.ProjectsServer

  def init(_params) do
    {ref, projects} = Projects.subscribe(@server, self())
    {:ok, Topic.new(projects, %{ref: ref})}
  end

  def handle_execute("create_project", {project_name, environment_name}, topic, _context) do
    case Projects.create_project(@server, project_name, environment_name) do
      {:ok, project_id} ->
        # TODO: update topic?
        case Orchestration.Supervisor.get_server(project_id, environment_name) do
          {:ok, _server} ->
            {:ok, [true, project_id], topic}
        end

      {:error, errors} ->
        {:ok, [false, Enum.map(errors, &Atom.to_string/1)], topic}
    end
  end

  def handle_execute("add_environment", {project_id, environment_name}, topic, _context) do
    case Projects.add_environment(@server, project_id, environment_name) do
      :ok ->
        {:ok, [true, nil], topic}

      {:error, errors} ->
        {:ok, [false, Enum.map(errors, &Atom.to_string/1)], topic}
    end
  end

  def handle_info({:project, _ref, project_id, project}, topic) do
    topic = Topic.set(topic, [project_id], project)
    {:ok, topic}
  end
end

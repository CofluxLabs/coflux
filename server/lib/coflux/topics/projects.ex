defmodule Coflux.Topics.Projects do
  alias Coflux.Orchestration
  use Topical.Topic, route: ["projects"]

  def init(_params) do
    schedule_tick()
    {:ok, Topic.new(find_projects())}
  end

  def handle_info(:tick, topic) do
    # TODO: update with changes
    topic = Topic.set(topic, [], find_projects())
    schedule_tick()
    {:ok, topic}
  end

  def handle_execute("create_project", {project_id, environment}, topic, _context) do
    # TODO: validate
    case Orchestration.Supervisor.get_server(project_id, environment) do
      {:ok, _server} ->
        topic = Topic.set(topic, [], find_projects())
        {:ok, nil, topic}
    end
  end

  defp find_projects() do
    "data"
    |> File.ls!()
    |> Map.new(fn project_id ->
      {project_id, %{"environments" => File.ls!("data/#{project_id}")}}
    end)
  end

  defp schedule_tick() do
    Process.send_after(self(), :tick, 10_000)
  end
end

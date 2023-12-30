defmodule Coflux.Projects do
  use GenServer

  alias Coflux.Utils

  def start_link(opts) do
    GenServer.start_link(__MODULE__, {}, opts)
  end

  def create_project(server, project_name, environment_name) do
    GenServer.call(server, {:create_project, project_name, environment_name})
  end

  def add_environment(server, project_id, environment_name) do
    GenServer.call(server, {:add_environment, project_id, environment_name})
  end

  def get_project_by_id(server, project_id) do
    GenServer.call(server, {:get_project_by_id, project_id})
  end

  def subscribe(server, pid) do
    GenServer.call(server, {:subscribe, pid})
  end

  def unsubscribe(server, ref) do
    GenServer.cast(server, {:unsubscribe, ref})
  end

  def init({}) do
    path = get_path()

    projects =
      if File.exists?(path) do
        path
        |> File.read!()
        |> Jason.decode!()
        |> Map.new(fn {project_id, project} ->
          {project_id, build_project(project)}
        end)
      else
        %{}
      end

    {:ok, %{projects: projects, subscribers: %{}}}
  end

  def handle_call({:create_project, project_name, environment_name}, _from, state) do
    # TODO: validate
    project_id = generate_id(state)

    state =
      put_in(
        state.projects[project_id],
        %{name: project_name, environments: [environment_name]}
      )

    save_projects(state)
    notify_subscribers(state, project_id)
    {:reply, {:ok, project_id}, state}
  end

  def handle_call({:add_environment, project_id, environment_name}, _from, state) do
    # TODO: validate
    state = update_in(state.projects[project_id].environments, &(&1 ++ environment_name))
    save_projects(state)
    notify_subscribers(state, project_id)
    {:noreply, :ok, state}
  end

  def handle_call({:get_project_by_id, project_id}, _from, state) do
    {:reply, Map.fetch(state.projects, project_id), state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    ref = Process.monitor(pid)
    state = put_in(state.subscribers[ref], pid)
    {:reply, {ref, state.projects}, state}
  end

  def handle_cast({:unsubscribe, ref}, state) do
    state = remove_subscriber(state, ref)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    state = remove_subscriber(state, ref)
    {:noreply, state}
  end

  defp get_path() do
    "data/projects.json"
  end

  defp remove_subscriber(state, ref) do
    pop_in(state.subscribers[ref])
  end

  defp notify_subscribers(state, project_id) do
    Enum.each(state.subscribers, fn {ref, pid} ->
      project = Map.fetch!(state.projects, project_id)
      send(pid, {:project, ref, project_id, project})
    end)
  end

  defp save_projects(state) do
    content = Jason.encode!(state.projects)
    File.write!(get_path(), content)
  end

  def generate_id(state, length \\ 5) do
    id = Utils.generate_id(length, "p")

    if Map.has_key?(state.projects, id) do
      generate_id(state, length + 1)
    else
      id
    end
  end

  defp build_project(project) do
    %{
      name: Map.fetch!(project, "name"),
      environments: Map.fetch!(project, "environments")
    }
  end
end

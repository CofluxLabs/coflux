defmodule Coflux.Project.Observer.Topics.Environments do
  alias Coflux.Project.Store
  alias Coflux.Project.Models

  def models(),
    do: [Models.Environment]

  def load(project_id, []) do
    with {:ok, environments} <- Store.list_environments(project_id) do
      value =
        Map.new(environments, fn environment ->
          {environment.id, Map.take(environment, [:id, :name])}
        end)

      {:ok, value, %{project_id: project_id}}
    end
  end

  def handle_insert(%Models.Environment{} = environment, _value, state) do
    {:ok, [{[environment.id], Map.take(environment, [:id, :name])}], state}
  end
end

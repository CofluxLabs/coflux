defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  @primary_key false
  schema "dependencies" do
    field :execution_id, :binary_id, primary_key: true
    field :dependency_id, :binary_id, primary_key: true
    field :created_at, :utc_datetime_usec
  end
end

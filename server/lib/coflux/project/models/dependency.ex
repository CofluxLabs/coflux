defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  @primary_key false
  schema "dependencies" do
    belongs_to :execution, Models.Execution, primary_key: true
    belongs_to :dependency, Models.Execution, foreign_key: :dependency_id, primary_key: true
    field :created_at, :utc_datetime_usec
  end
end

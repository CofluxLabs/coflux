defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  schema "dependencies" do
    belongs_to :execution, Models.Execution
    belongs_to :dependency, Models.Execution, foreign_key: :dependency_id
    field :created_at, :utc_datetime
  end
end

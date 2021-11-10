defmodule Coflux.Project.Models.Execution do
  use Coflux.Project.Model

  schema "executions" do
    belongs_to :step, Models.Step
    field :version, :string
    field :execute_after, :utc_datetime
    field :created_at, :utc_datetime_usec

    has_many :child_steps, Models.Step, foreign_key: :parent_id
    has_many :dependencies, Models.Dependency
    has_many :dependents, Models.Dependency, foreign_key: :dependency_id
    has_many :acknowledgments, Models.Acknowledgment
    has_one :assignment, Models.Assignment
  end
end

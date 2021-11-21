defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  @primary_key false
  schema "dependencies" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :step, Models.Step, type: Types.StepId, primary_key: true
    belongs_to :execution, Models.Execution, foreign_key: :attempt, references: :attempt, type: :integer, primary_key: true
    belongs_to :dependency_run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :dependency_step, Models.Step, type: Types.StepId, primary_key: true
    belongs_to :dependency_execution, Models.Execution, foreign_key: :dependency_attempt, references: :attempt, type: :integer, primary_key: true
    field :created_at, :utc_datetime_usec
  end

  def from_step_id(dependency) do
    encode_step_id(dependency.run_id, dependency.step_id)
  end

  def from_execution_id(dependency) do
    encode_execution_id(dependency.run_id, dependency.step_id, dependency.attempt)
  end

  def to_execution_id(dependency) do
    encode_execution_id(dependency.dependency_run_id, dependency.dependency_step_id, dependency.dependency_attempt)
  end
end

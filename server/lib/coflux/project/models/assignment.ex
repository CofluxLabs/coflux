defmodule Coflux.Project.Models.Assignment do
  use Coflux.Project.Model

  @primary_key false
  schema "assignments" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :step, Models.Step, type: Types.StepId, primary_key: true
    belongs_to :execution, Models.Execution, foreign_key: :attempt, references: :attempt, type: :integer, primary_key: true
    field :created_at, :utc_datetime_usec
  end

  def step_id(assignment) do
    encode_step_id(assignment.run_id, assignment.step_id)
  end

  def execution_id(assignment) do
    encode_execution_id(assignment.run_id, assignment.step_id, assignment.attempt)
  end
end

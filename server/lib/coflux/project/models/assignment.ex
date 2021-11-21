defmodule Coflux.Project.Models.Assignment do
  use Coflux.Project.Model

  @primary_key false
  schema "assignments" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
    field :created_at, :utc_datetime_usec
  end

  def step_id(assignment) do
    encode_step_id(assignment.run_id, assignment.step_id)
  end

  def execution_id(assignment) do
    encode_execution_id(assignment.run_id, assignment.step_id, assignment.attempt)
  end
end

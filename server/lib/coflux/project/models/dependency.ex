defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  @primary_key false
  schema "dependencies" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
    field :dependency_run_id, Types.RunId, primary_key: true
    field :dependency_step_id, Types.StepId, primary_key: true
    field :dependency_attempt, :integer, primary_key: true
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

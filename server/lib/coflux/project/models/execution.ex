defmodule Coflux.Project.Models.Execution do
  use Coflux.Project.Model

  @primary_key false
  schema "executions" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
    field :version, :string
    field :execute_after, :utc_datetime
    field :created_at, :utc_datetime_usec
  end

  def step_id(execution) do
    encode_step_id(execution.run_id, execution.step_id)
  end

  def id(execution) do
    encode_execution_id(execution.run_id, execution.step_id, execution.attempt)
  end
end

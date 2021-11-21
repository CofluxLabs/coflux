defmodule Coflux.Project.Models.Result do
  use Coflux.Project.Model

  @primary_key false
  schema "results" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :step, Models.Step, type: Types.StepId, primary_key: true
    belongs_to :execution, Models.Execution, foreign_key: :attempt, references: :attempt, type: :integer, primary_key: true
    field :type, :integer
    field :value, :string
    field :extra, :map
    field :created_at, :utc_datetime_usec
  end

  def step_id(result) do
    encode_step_id(result.run_id, result.step_id)
  end

  def execution_id(result) do
    encode_execution_id(result.run_id, result.step_id, result.attempt)
  end
end

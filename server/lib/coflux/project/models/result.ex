defmodule Coflux.Project.Models.Result do
  use Coflux.Project.Model

  @primary_key false
  schema "results" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
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

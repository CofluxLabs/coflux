defmodule Coflux.Project.Models.Step do
  use Coflux.Project.Model

  @primary_key false
  schema "steps" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    field :id, Types.StepId, primary_key: true
    belongs_to :parent_step, Models.Step, type: Types.StepId
    belongs_to :parent_execution, Models.Execution, foreign_key: :parent_attempt, references: :attempt, type: :integer
    belongs_to :cached_run, Models.Run, type: Types.RunId
    belongs_to :cached_step, Models.Step, type: Types.StepId
    field :repository, :string
    field :target, :string
    field :arguments, {:array, :string}
    field :tags, {:array, :string}
    field :priority, :integer
    field :cache_key, :string
    field :created_at, :utc_datetime_usec

    has_many :executions, Models.Execution, references: :id, preload_order: [:created_at]
  end

  def id(step) do
    encode_step_id(step.run_id, step.id)
  end

  def parent_id(step) do
    if step.parent_step_id do
      encode_execution_id(step.run_id, step.parent_step_id, step.parent_attempt)
    end
  end

  def cached_id(step) do
    if step.cached_step_id do
      encode_step_id(step.cached_run_id, step.cached_step_id)
    end
  end
end

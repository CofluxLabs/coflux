defmodule Coflux.Project.Models.Execution do
  use Coflux.Project.Model

  @primary_key false
  schema "executions" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :step, Models.Step, type: Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
    field :version, :string
    field :execute_after, :utc_datetime
    field :created_at, :utc_datetime_usec

    has_many :child_steps, Models.Step, foreign_key: :parent_attempt, references: :attempt
    has_many :dependencies, Models.Dependency, foreign_key: :attempt, references: :attempt
    has_many :dependents, Models.Dependency, foreign_key: :dependency_attempt, references: :attempt
    has_many :heartbeats, Models.Heartbeat, foreign_key: :attempt, references: :attempt
    has_one :latest_heartbeat, Models.Heartbeat, foreign_key: :attempt, references: :attempt
    has_one :assignment, Models.Assignment, foreign_key: :attempt, references: :attempt
    has_one :result, Models.Result, foreign_key: :attempt, references: :attempt
  end

  def step_id(execution) do
    encode_step_id(execution.run_id, execution.step_id)
  end

  def id(execution) do
    encode_execution_id(execution.run_id, execution.step_id, execution.attempt)
  end
end

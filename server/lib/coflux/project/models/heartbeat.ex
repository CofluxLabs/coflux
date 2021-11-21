defmodule Coflux.Project.Models.Heartbeat do
  use Coflux.Project.Model

  @primary_key false
  schema "heartbeats" do
    belongs_to :run, Models.Run, type: Types.RunId, primary_key: true
    belongs_to :step, Models.Step, type: Types.StepId, primary_key: true
    belongs_to :execution, Models.Execution, foreign_key: :attempt, references: :attempt, type: :integer, primary_key: true
    field :created_at, :utc_datetime_usec, primary_key: true
  end

  def execution_id(heartbeat) do
    encode_execution_id(heartbeat.run_id, heartbeat.step_id, heartbeat.attempt)
  end
end

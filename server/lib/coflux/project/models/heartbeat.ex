defmodule Coflux.Project.Models.Heartbeat do
  use Coflux.Project.Model

  @primary_key false
  schema "heartbeats" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :attempt, :integer, primary_key: true
    field :created_at, :utc_datetime_usec, primary_key: true
    field :status, :integer
  end

  def execution_id(heartbeat) do
    encode_execution_id(heartbeat.run_id, heartbeat.step_id, heartbeat.attempt)
  end
end

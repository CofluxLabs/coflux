defmodule Coflux.Project.Models.Attempt do
  use Coflux.Project.Model

  @primary_key false
  schema "attempts" do
    field :run_id, Types.RunId, primary_key: true
    field :step_id, Types.StepId, primary_key: true
    field :number, :integer, primary_key: true
    belongs_to :execution, Models.Execution
    field :created_at, :utc_datetime_usec
  end
end

defmodule Coflux.Project.Models.Heartbeat do
  use Coflux.Project.Model

  @primary_key false
  schema "heartbeats" do
    belongs_to :execution, Models.Execution
    field :created_at, :utc_datetime_usec
  end
end

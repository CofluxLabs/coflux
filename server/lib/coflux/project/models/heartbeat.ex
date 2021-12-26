defmodule Coflux.Project.Models.Heartbeat do
  use Coflux.Project.Model

  @primary_key false
  schema "heartbeats" do
    belongs_to :execution, Models.Execution, type: :binary_id, primary_key: true
    field :created_at, :utc_datetime_usec, primary_key: true
    field :status, :integer
  end
end

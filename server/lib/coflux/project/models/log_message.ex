defmodule Coflux.Project.Models.LogMessage do
  use Coflux.Project.Model

  schema "log_messages" do
    belongs_to :execution, Models.Execution, type: :binary_id
    field :level, :integer
    field :message, :string
    field :created_at, :utc_datetime_usec
  end
end

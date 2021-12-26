defmodule Coflux.Project.Models.Assignment do
  use Coflux.Project.Model

  @primary_key false
  schema "assignments" do
    belongs_to :execution, Models.Execution, type: :binary_id, primary_key: true
    belongs_to :session, Models.Session, type: :binary_id
    field :created_at, :utc_datetime_usec
  end
end

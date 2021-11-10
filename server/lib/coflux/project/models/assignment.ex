defmodule Coflux.Project.Models.Assignment do
  use Coflux.Project.Model

  @primary_key false
  schema "assignments" do
    belongs_to :execution, Models.Execution, primary_key: true
    field :created_at, :utc_datetime
  end
end

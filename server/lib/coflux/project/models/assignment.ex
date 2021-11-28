defmodule Coflux.Project.Models.Assignment do
  use Coflux.Project.Model

  @primary_key false
  schema "assignments" do
    field :execution_id, :binary_id, primary_key: true
    field :created_at, :utc_datetime_usec
  end
end

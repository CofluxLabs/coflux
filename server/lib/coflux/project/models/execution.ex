defmodule Coflux.Project.Models.Execution do
  use Coflux.Project.Model

  schema "executions" do
    field :repository, :string
    field :target, :string
    field :arguments, {:array, :string}
    field :tags, {:array, :string}
    field :priority, :integer
    field :version, :string
    field :execute_after, :utc_datetime
    field :created_at, :utc_datetime_usec
  end
end

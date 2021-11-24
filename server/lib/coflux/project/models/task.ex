defmodule Coflux.Project.Models.Task do
  use Coflux.Project.Model

  schema "tasks" do
    field :repository, :string
    field :version, :string
    field :target, :string
    field :parameters, {:array, :map}
    field :created_at, :utc_datetime_usec

    has_many :runs, Models.Run
  end
end

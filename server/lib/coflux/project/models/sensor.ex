defmodule Coflux.Project.Models.Sensor do
  use Coflux.Project.Model

  schema "sensors" do
    field :repository, :string
    field :version, :string
    field :target, :string
    field :created_at, :utc_datetime_usec
  end
end

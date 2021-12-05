defmodule Coflux.Project.Models.Manifest do
  use Coflux.Project.Model

  schema "manifests" do
    field :repository, :string
    field :version, :string
    field :hash, :binary
    field :tasks, :map
    field :sensors, {:array, :string}
    field :created_at, :utc_datetime_usec
  end
end

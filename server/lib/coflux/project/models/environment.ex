defmodule Coflux.Project.Models.Environment do
  use Coflux.Project.Model

  schema "environments" do
    field :name, :string
    field :created_at, :utc_datetime_usec
  end
end

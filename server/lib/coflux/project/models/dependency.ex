defmodule Coflux.Project.Models.Dependency do
  use Coflux.Project.Model

  schema "dependencies" do
    field :created_at, :utc_datetime_usec
  end
end

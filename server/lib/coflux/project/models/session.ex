defmodule Coflux.Project.Models.Session do
  use Coflux.Project.Model

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field :created_at, :utc_datetime_usec
  end
end

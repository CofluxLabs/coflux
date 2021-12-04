defmodule Coflux.Project.Models.Cursor do
  use Coflux.Project.Model

  @primary_key false
  schema "cursors" do
    field :execution_id, :binary_id, primary_key: true
    field :sequence, :integer
    field :type, :integer
    field :value, :string
    field :created_at, :utc_datetime_usec
  end
end

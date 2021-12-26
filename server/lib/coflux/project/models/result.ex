defmodule Coflux.Project.Models.Result do
  use Coflux.Project.Model

  @primary_key false
  schema "results" do
    belongs_to :execution, Models.Execution, type: :binary_id, primary_key: true
    field :type, :integer
    field :value, :string
    field :extra, :map
    field :created_at, :utc_datetime_usec
  end
end

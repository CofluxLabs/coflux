defmodule Coflux.Project.Models.Result do
  use Coflux.Project.Model

  @primary_key false
  schema "results" do
    belongs_to :execution, Models.Execution, primary_key: true
    field :type, :integer
    field :value, :string
    field :extra, :map
    field :created_at, :utc_datetime
  end
end

defmodule Coflux.Project.Models.Step do
  use Coflux.Project.Model

  schema "steps" do
    belongs_to :run, Models.Run
    belongs_to :parent, Models.Execution
    belongs_to :cached_step, Models.Step
    field :repository, :string
    field :target, :string
    field :arguments, {:array, :string}
    field :tags, {:array, :string}
    field :priority, :integer
    field :cache_key, :string
    field :created_at, :utc_datetime_usec

    has_many :executions, Models.Execution, preload_order: [:created_at]
  end
end

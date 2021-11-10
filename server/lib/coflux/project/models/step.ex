defmodule Coflux.Project.Models.Step do
  use Coflux.Project.Model

  schema "steps" do
    belongs_to :run, Models.Run
    belongs_to :parent, Models.Execution
    field :repository, :string
    field :target, :string
    field :tags, {:array, :string}
    field :priority, :integer
    field :created_at, :utc_datetime_usec

    has_many :arguments, Models.StepArgument, preload_order: [:index]
    has_many :executions, Models.Execution
  end
end

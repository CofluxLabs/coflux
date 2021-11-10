defmodule Coflux.Project.Models.Run do
  use Coflux.Project.Model

  schema "runs" do
    belongs_to :task, Models.Task
    field :tags, {:array, :string}

    has_many :steps, Models.Step
  end
end

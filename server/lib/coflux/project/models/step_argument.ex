defmodule Coflux.Project.Models.StepArgument do
  use Coflux.Project.Model

  @primary_key false
  schema "step_arguments" do
    belongs_to :step, Models.Step, primary_key: true
    field :index, :integer, primary_key: true
    field :type, :integer
    field :value, :string
  end
end

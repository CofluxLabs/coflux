defmodule Coflux.Project.Models.SensorIteration do
  use Coflux.Project.Model

  @primary_key false
  schema "sensor_iterations" do
    belongs_to :activation, Models.SensorActivation
    field :sequence, :integer
    belongs_to :execution, Models.Execution, type: :binary_id
    field :created_at, :utc_datetime_usec
  end
end

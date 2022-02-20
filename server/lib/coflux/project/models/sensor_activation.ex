defmodule Coflux.Project.Models.SensorActivation do
  use Coflux.Project.Model

  schema "sensor_activations" do
    field :repository, :string
    field :target, :string
    belongs_to :environment, Models.Environment
    field :created_at, :utc_datetime_usec
  end
end

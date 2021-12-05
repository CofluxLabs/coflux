defmodule Coflux.Project.Models.SensorActivation do
  use Coflux.Project.Model

  schema "sensor_activations" do
    field :repository, :string
    field :target, :string
    field :tags, {:array, :string}
    field :created_at, :utc_datetime_usec
  end
end

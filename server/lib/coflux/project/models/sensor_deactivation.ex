defmodule Coflux.Project.Models.SensorDeactivation do
  use Coflux.Project.Model

  @primary_key false
  schema "sensor_deactivations" do
    belongs_to :activation, Models.SensorActivation
    field :created_at, :utc_datetime_usec
  end
end

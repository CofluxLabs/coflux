defmodule Coflux.Project.Models.Acknowledgment do
  use Coflux.Project.Model

  schema "acknowledgments" do
    belongs_to :execution, Models.Execution
    field :created_at, :utc_datetime_usec
  end
end

defmodule Coflux.Project.Models.Run do
  use Coflux.Project.Model

  @primary_key {:id, Types.RunId, []}
  schema "runs" do
    belongs_to :environment, Models.Environment
    belongs_to :execution, Models.Execution, type: :binary_id
    field :idempotency_key, :string
    field :created_at, :utc_datetime_usec

    has_many :steps, Models.Step, preload_order: [:created_at]
  end
end

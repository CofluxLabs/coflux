defmodule Coflux.Orchestration.Models do
  defmodule Run do
    def prepare(fields) do
      Keyword.update!(fields, :recurrent, &(&1 > 0))
    end

    defstruct [
      :id,
      :external_id,
      :parent_id,
      :idempotency_key,
      :recurrent,
      :created_at
    ]
  end

  defmodule Step do
    defstruct [
      :id,
      :external_id,
      :run_id,
      :parent_id,
      :repository,
      :target,
      :priority,
      :cache_key,
      :retry_count,
      :retry_delay_min,
      :retry_delay_max,
      :created_at
    ]
  end
end

defmodule Coflux.Store.Models do
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

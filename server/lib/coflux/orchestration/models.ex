defmodule Coflux.Orchestration.Models do
  defmodule Utils do
    def decode_wait_for(value) do
      if value do
        value
        |> Integer.digits(2)
        |> Enum.reverse()
        |> Enum.with_index()
        |> Enum.filter(fn
          {0, _} -> false
          {1, _} -> true
        end)
        |> Enum.map(fn {_, i} -> i end)
      end
    end
  end

  defmodule Run do
    defstruct [
      :id,
      :external_id,
      :parent_id,
      :idempotency_key,
      :recurrent,
      :created_at
    ]

    def prepare(fields) do
      Keyword.update!(fields, :recurrent, &(&1 > 0))
    end
  end

  defmodule Step do
    alias Utils

    defstruct [
      :id,
      :external_id,
      :run_id,
      :parent_id,
      :repository,
      :target,
      :priority,
      :wait_for,
      :cache_key,
      :retry_count,
      :retry_delay_min,
      :retry_delay_max,
      :created_at
    ]

    def prepare(fields) do
      Keyword.update!(fields, :wait_for, &Utils.decode_wait_for/1)
    end
  end

  defmodule UnassignedExecution do
    defstruct [
      :execution_id,
      :step_id,
      :run_id,
      :run_external_id,
      :run_recurrent,
      :repository,
      :target,
      :wait_for,
      :defer_key,
      :parent_id,
      :requires_tag_set_id,
      :environment_id,
      :execute_after,
      :created_at
    ]

    def prepare(fields) do
      fields
      |> Keyword.update!(:wait_for, &Utils.decode_wait_for/1)
      |> Keyword.update!(:run_recurrent, &(&1 > 0))
    end
  end
end

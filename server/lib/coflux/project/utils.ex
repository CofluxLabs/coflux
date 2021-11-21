defmodule Coflux.Project.Utils do
  def encode_step_id(run_id, step_id) do
    "#{run_id}-#{step_id}"
  end

  def encode_execution_id(run_id, step_id, attempt) do
    "#{run_id}-#{step_id}-#{format_attempt(attempt)}"
  end

  def decode_execution_id(execution_id) do
    [run_id, step_id, attempt] = String.split(execution_id, "-")
    {run_id, step_id, String.to_integer(attempt)}
  end

  defp format_attempt(attempt) do
    attempt
    |> Integer.to_string()
    |> String.pad_leading(2, "0")
  end
end
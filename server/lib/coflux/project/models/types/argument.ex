defmodule Coflux.Project.Models.Types.Argument do
  use Ecto.Type

  def type, do: :string

  def cast(value) do
    # TODO: handle other formats?
    load(value)
  end

  def dump(value) do
    case value do
      {:json, json} -> {:ok, "json:#{json}"}
      {:result, execution_id} -> {:ok, "result:#{execution_id}"}
      {:blob, hash} -> {:ok, "blob:#{hash}"}
      _other -> :error
    end
  end

  def load(data) do
    case data do
      "json:" <> json -> {:ok, {:json, json}}
      "result:" <> execution_id -> {:ok, {:result, execution_id}}
      "blob:" <> hash -> {:ok, {:blob, hash}}
      _other -> :error
    end
  end
end

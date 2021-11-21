defmodule Coflux.Project.Models.Types.RunId do
  use Ecto.Type

  def type, do: :binary

  def cast(id) do
    case id do
      <<id::binary-size(10)>> ->
        {:ok, encode(id)}

      <<id::binary-size(16)>> ->
        {:ok, id}

      "\\x" <> <<hex::binary-size(20)>> ->
        {:ok, encode(Base.decode16!(hex, case: :lower))}

      _other ->
        :error
    end
  end

  def dump(id) do
    case id do
      <<id::binary-size(16)>> ->
        Base.decode32(id)

      _other ->
        :error
    end
  end

  def load(id) do
    case id do
      <<id::binary-size(10)>> ->
        {:ok, encode(id)}

      _other ->
        :error
    end
  end

  defp encode(value) do
    Base.encode32(value)
  end
end

defmodule Coflux.Utils do
  @id_chars String.codepoints("bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ23456789")

  def generate_id(length, prefix \\ "") do
    prefix <> Enum.map_join(0..length, fn _ -> Enum.random(@id_chars) end)
  end
end

defmodule Coflux.Utils do
  @id_chars String.codepoints("bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ23456789")

  def generate_id(length, prefix \\ "") do
    prefix <> Enum.map_join(0..length, fn _ -> Enum.random(@id_chars) end)
  end

  def data_path(path) do
    path =
      "COFLUX_DATA_DIR"
      |> System.get_env(Path.join(File.cwd!(), "data"))
      |> Path.join(path)

    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    path
  end
end

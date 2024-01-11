defmodule Coflux.MapUtils do
  def delete_in(map, []) do
    map
  end

  def delete_in(map_set = %MapSet{}, [key]) do
    MapSet.delete(map_set, key)
  end

  def delete_in(map, [key]) do
    Map.delete(map, key)
  end

  def delete_in(map, [key | rest]) do
    case Map.get(map, key) do
      value when is_map(value) ->
        result = delete_in(value, rest)

        if Enum.empty?(result) do
          Map.delete(map, key)
        else
          Map.put(map, key, result)
        end

      _ ->
        map
    end
  end

  def translate_keys(map, translations) do
    Map.new(map, fn {key, value} ->
      {Map.get(translations, key, key), value}
    end)
  end
end

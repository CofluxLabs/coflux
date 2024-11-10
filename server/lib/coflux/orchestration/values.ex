defmodule Coflux.Orchestration.Values do
  import Coflux.Store

  # TODO: move, or make private?
  def get_or_create_blob(db, blob_key, size) do
    case query_one(db, "SELECT id FROM blobs WHERE key = ?1", {blob_key}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        insert_one(db, :blobs, %{
          key: blob_key,
          size: size
        })
    end
  end

  def get_value_by_id(db, value_id) do
    case query_one!(
           db,
           """
           SELECT v.content, b.key, b.size
           FROM values_ AS v
           LEFT JOIN blobs AS b ON b.id = v.blob_id
           WHERE v.id = ?1
           """,
           {value_id}
         ) do
      {:ok, {content, blob_key, size}} ->
        references =
          case query(
                 db,
                 """
                 SELECT block_id, execution_id, asset_id
                 FROM value_references
                 WHERE value_id = ?1
                 ORDER BY position
                 """,
                 {value_id}
               ) do
            {:ok, rows} ->
              Enum.map(rows, fn
                {block_id, nil, nil} -> load_block(db, block_id)
                {nil, execution_id, nil} -> {:execution, execution_id}
                {nil, nil, asset_id} -> {:asset, asset_id}
              end)
          end

        value =
          case {content, blob_key} do
            {content, nil} ->
              {:raw, Jason.decode!(content), references}

            {nil, blob_key} ->
              {:blob, blob_key, size, references}
          end

        {:ok, value}
    end
  end

  defp load_block(db, block_id) do
    case query_one(
           db,
           """
           SELECT s.name, b.key, b.size
           FROM blocks AS k
           INNER JOIN serialisers AS s ON s.id = k.serialiser_id
           INNER JOIN blobs AS b ON b.id = k.blob_id
           WHERE k.id = ?1
           """,
           {block_id}
         ) do
      {:ok, {serialiser, blob_key, size}} ->
        metadata =
          case query(
                 db,
                 "SELECT key, value FROM block_metadata WHERE block_id = ?1",
                 {block_id}
               ) do
            {:ok, rows} ->
              Map.new(rows, fn {key, value} -> {key, Jason.decode!(value)} end)
          end

        {:block, serialiser, blob_key, size, metadata}
    end
  end

  defp hash_value(data, blob_id, references) do
    reference_parts =
      Enum.flat_map(references, fn reference ->
        case reference do
          {:block, serialiser, blob_key, _size, metadata} ->
            Enum.concat(
              [1, serialiser, blob_key],
              Enum.flat_map(metadata, fn {key, value} -> [key, Jason.encode!(value)] end)
            )

          {:execution, execution_id} ->
            [2, Integer.to_string(execution_id)]

          {:asset, asset_id} ->
            [3, Integer.to_string(asset_id)]
        end
      end)

    data =
      [
        if(!is_nil(data), do: Jason.encode!(data), else: 0),
        if(blob_id, do: Integer.to_string(blob_id), else: 0)
      ]
      |> Enum.concat(reference_parts)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  def get_or_create_value(db, value) do
    {data, blob_id, references} =
      case value do
        {:raw, data, references} ->
          {data, nil, references}

        {:blob, blob_key, size, references} ->
          {:ok, blob_id} = get_or_create_blob(db, blob_key, size)
          {nil, blob_id, references}
      end

    hash = hash_value(data, blob_id, references)

    case query_one(db, "SELECT id FROM values_ WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, value_id} =
          insert_one(db, :values_, %{
            hash: hash,
            content: unless(blob_id, do: Jason.encode!(data)),
            blob_id: blob_id
          })

        {:ok, _} =
          insert_many(
            db,
            :value_references,
            {:value_id, :position, :block_id, :execution_id, :asset_id},
            references
            |> Enum.with_index()
            |> Enum.map(fn {reference, position} ->
              case reference do
                {:block, serialiser, blob_key, size, metadata} ->
                  {:ok, block_id} =
                    get_or_create_block(db, serialiser, blob_key, size, metadata)

                  {value_id, position, block_id, nil, nil}

                {:execution, execution_id} ->
                  {value_id, position, nil, execution_id, nil}

                {:asset, asset_id} ->
                  {value_id, position, nil, nil, asset_id}
              end
            end)
          )

        {:ok, value_id}
    end
  end

  defp get_or_create_serialiser(db, name) do
    case query_one(db, "SELECT id FROM serialisers WHERE name = ?1", {name}) do
      {:ok, {id}} -> {:ok, id}
      {:ok, nil} -> insert_one(db, :serialisers, %{name: name})
    end
  end

  defp hash_block(serialiser, blob_key, metadata) do
    metadata_parts =
      Enum.flat_map(metadata, fn {key, value} -> [key, Jason.encode!(value)] end)

    data =
      [serialiser, blob_key]
      |> Enum.concat(metadata_parts)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  defp get_or_create_block(db, serialiser, blob_key, size, metadata) do
    hash = hash_block(serialiser, blob_key, metadata)

    case query_one(db, "SELECT id FROM blocks WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, serialiser_id} = get_or_create_serialiser(db, serialiser)
        {:ok, blob_id} = get_or_create_blob(db, blob_key, size)

        {:ok, block_id} =
          insert_one(db, :blocks, %{
            hash: hash,
            serialiser_id: serialiser_id,
            blob_id: blob_id
          })

        {:ok, _} =
          insert_many(
            db,
            :block_metadata,
            {:block_id, :key, :value},
            Enum.map(metadata, fn {key, value} ->
              {block_id, key, Jason.encode!(value)}
            end)
          )

        {:ok, block_id}
    end
  end
end

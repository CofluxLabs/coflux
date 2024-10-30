defmodule Coflux.Orchestration.Results do
  import Coflux.Store

  def record_checkpoint(db, execution_id, arguments) do
    with_transaction(db, fn ->
      sequence =
        case query_one(
               db,
               """
               SELECT MAX(sequence)
               FROM checkpoints
               WHERE execution_id = ?1
               """,
               {execution_id}
             ) do
          {:ok, {nil}} -> 1
          {:ok, {max_sequence}} -> max_sequence + 1
        end

      now = current_timestamp()

      {:ok, checkpoint_id} = insert_checkpoint(db, execution_id, sequence, now)

      arguments
      |> Enum.with_index()
      |> Enum.each(fn {value, position} ->
        {:ok, value_id} = get_or_create_value(db, value, now)
        {:ok, _} = insert_checkpoint_argument(db, checkpoint_id, position, value_id)
      end)

      {:ok, checkpoint_id, sequence, now}
    end)
  end

  def get_latest_checkpoint(db, step_id) do
    query_one(
      db,
      """
      SELECT c.id, c.execution_id, c.sequence, c.created_at
      FROM checkpoints AS c
      INNER JOIN executions AS e ON e.id = c.execution_id
      WHERE e.step_id = ?1
      ORDER BY e.attempt DESC, c.sequence DESC
      LIMIT 1
      """,
      {step_id}
    )
  end

  def get_checkpoint_arguments(db, checkpoint_id) do
    case query(
           db,
           """
           SELECT value_id
           FROM checkpoint_arguments
           WHERE checkpoint_id = ?1
           ORDER BY position
           """,
           {checkpoint_id}
         ) do
      {:ok, rows} ->
        values =
          Enum.map(rows, fn {value_id} ->
            case get_value_by_id(db, value_id) do
              {:ok, value} -> value
            end
          end)

        {:ok, values}
    end
  end

  def record_result(db, execution_id, result) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {type, error_id, value_id, successor_id} =
        case result do
          {:error, type, message, frames, retry_id} ->
            {:ok, error_id} = get_or_create_error(db, type, message, frames)
            {0, error_id, nil, retry_id}

          {:value, value} ->
            {:ok, value_id} = get_or_create_value(db, value, now)
            {1, nil, value_id, nil}

          {:abandoned, retry_id} ->
            {2, nil, nil, retry_id}

          :cancelled ->
            {3, nil, nil, nil}

          {:deferred, defer_id} ->
            {4, nil, nil, defer_id}

          {:suspended, successor_id} ->
            {6, nil, nil, successor_id}
        end

      case insert_result(db, execution_id, type, error_id, value_id, successor_id, now) do
        {:ok, _} ->
          {:ok, now}

        {:error, "UNIQUE constraint failed: " <> _field} ->
          {:error, :already_recorded}
      end
    end)
  end

  def has_result?(db, execution_id) do
    case query_one(db, "SELECT COUNT(*) FROM results WHERE execution_id = ?1", {execution_id}) do
      {:ok, {0}} -> {:ok, false}
      {:ok, {1}} -> {:ok, true}
    end
  end

  def get_result(db, execution_id) do
    case query_one(
           db,
           """
           SELECT type, error_id, value_id, successor_id, created_at
           FROM results
           WHERE execution_id = ?1
           """,
           {execution_id}
         ) do
      {:ok, {type, error_id, value_id, successor_id, created_at}} ->
        result =
          case {type, error_id, value_id, successor_id} do
            {0, error_id, nil, retry_id} ->
              case get_error_by_id(db, error_id) do
                {:ok, {type, message, frames}} ->
                  {:error, type, message, frames, retry_id}
              end

            {1, nil, value_id, nil} ->
              case get_value_by_id(db, value_id) do
                {:ok, value} -> {:value, value}
              end

            {2, nil, nil, retry_id} ->
              {:abandoned, retry_id}

            {3, nil, nil, nil} ->
              :cancelled

            {4, nil, nil, defer_id} ->
              {:deferred, defer_id}

            {5, nil, nil, cached_id} ->
              {:cached, cached_id}

            {6, nil, nil, successor_id} ->
              {:suspended, successor_id}
          end

        {:ok, {result, created_at}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  defp get_error_by_id(db, error_id) do
    {:ok, {type, message}} =
      query_one!(db, "SELECT type, message FROM errors WHERE id = ?1", {error_id})

    {:ok, frames} =
      query(
        db,
        "SELECT file, line, name, code FROM error_frames WHERE error_id = ?1 ORDER BY depth",
        {error_id}
      )

    {:ok, {type, message, frames}}
  end

  defp get_or_create_blob(db, blob_key, size) do
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
        if(data, do: Jason.encode!(data), else: 0),
        if(blob_id, do: Integer.to_string(blob_id), else: 0)
      ]
      |> Enum.concat(reference_parts)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  def get_or_create_value(db, value, now) do
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
                    get_or_create_block(db, serialiser, blob_key, size, metadata, now)

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

  defp hash_error(type, message, frames) do
    frame_parts =
      Enum.flat_map(frames, fn {file, line, name, code} ->
        [file, Integer.to_string(line), name || 0, code || 0]
      end)

    parts = Enum.concat([type, message], frame_parts)
    :crypto.hash(:sha256, Enum.intersperse(parts, 0))
  end

  defp get_or_create_error(db, type, message, frames) do
    hash = hash_error(type, message, frames)

    case query_one(db, "SELECT id FROM errors WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, error_id} =
          insert_one(db, :errors, %{
            hash: hash,
            type: type,
            message: message
          })

        {:ok, _} =
          insert_many(
            db,
            :error_frames,
            {:error_id, :depth, :file, :line, :name, :code},
            frames
            |> Enum.with_index()
            |> Enum.map(fn {{file, line, name, code}, index} ->
              {error_id, index, file, line, name, code}
            end)
          )

        {:ok, error_id}
    end
  end

  def create_asset(db, execution_id, type, path, blob_key, size, metadata) do
    with_transaction(db, fn ->
      now = current_timestamp()
      {:ok, blob_id} = get_or_create_blob(db, blob_key, size)

      {:ok, asset_id} =
        insert_one(db, :assets, %{
          execution_id: execution_id,
          type: type,
          path: path,
          blob_id: blob_id,
          created_at: now
        })

      {:ok, _} =
        insert_many(
          db,
          :asset_metadata,
          {:asset_id, :key, :value},
          Enum.map(metadata, fn {key, value} ->
            {asset_id, key, Jason.encode!(value)}
          end)
        )

      {:ok, asset_id}
    end)
  end

  def get_asset_by_id(db, asset_id, load_metadata) do
    case query_one(
           db,
           """
           SELECT a.execution_id, a.type, a.path, b.key, b.size, a.created_at
           FROM assets AS a
           INNER JOIN blobs AS b ON b.id = a.blob_id
           WHERE a.id = ?1
           """,
           {asset_id}
         ) do
      {:ok, {execution_id, type, path, blob_key, size, created_at}} ->
        metadata =
          if load_metadata do
            case query(
                   db,
                   "SELECT key, value FROM asset_metadata WHERE asset_id = ?1",
                   {asset_id}
                 ) do
              {:ok, rows} ->
                Map.new(rows, fn {key, value} -> {key, Jason.decode!(value)} end)
            end
          end

        {:ok, {execution_id, type, path, blob_key, size, created_at, metadata}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  # TODO: get all assets for run?
  def get_assets_for_execution(db, execution_id) do
    case query(
           db,
           "SELECT id FROM assets WHERE execution_id = ?1",
           {execution_id}
         ) do
      {:ok, rows} ->
        {:ok, Enum.map(rows, fn {asset_id} -> asset_id end)}
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

  defp get_or_create_block(db, serialiser, blob_key, size, metadata, now) do
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
            blob_id: blob_id,
            created_at: now
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

  # TODO: make this private?
  def insert_result(
        db,
        execution_id,
        type,
        error_id,
        value_id,
        successor_id,
        created_at
      ) do
    insert_one(db, :results, %{
      execution_id: execution_id,
      type: type,
      error_id: error_id,
      value_id: value_id,
      successor_id: successor_id,
      created_at: created_at
    })
  end

  defp insert_checkpoint(db, execution_id, sequence, created_at) do
    insert_one(db, :checkpoints, %{
      execution_id: execution_id,
      sequence: sequence,
      created_at: created_at
    })
  end

  defp insert_checkpoint_argument(db, checkpoint_id, position, value_id) do
    insert_one(db, :checkpoint_arguments, %{
      checkpoint_id: checkpoint_id,
      position: position,
      value_id: value_id
    })
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end

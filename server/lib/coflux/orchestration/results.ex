defmodule Coflux.Orchestration.Results do
  import Coflux.Store

  alias Coflux.Orchestration.Values

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
        {:ok, value_id} = Values.get_or_create_value(db, value)
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
            case Values.get_value_by_id(db, value_id) do
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
            {:ok, value_id} = Values.get_or_create_value(db, value)
            {1, nil, value_id, nil}

          {:abandoned, retry_id} ->
            {2, nil, nil, retry_id}

          :cancelled ->
            {3, nil, nil, nil}

          {:deferred, defer_id} ->
            {4, nil, nil, defer_id}

          {:cached, cached_id} ->
            {5, nil, nil, cached_id}

          {:suspended, successor_id} ->
            {6, nil, nil, successor_id}

          {:spawned, execution_id} ->
            {7, nil, nil, execution_id}
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
              case Values.get_value_by_id(db, value_id) do
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

            {7, nil, nil, execution_id} ->
              {:spawned, execution_id}
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
            hash: {:blob, hash},
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

  defp hash_asset(type, path, blob_key, metadata) do
    metadata_parts =
      Enum.flat_map(metadata, fn {key, value} -> [key, Jason.encode!(value)] end)

    data =
      [type, path, blob_key]
      |> Enum.concat(metadata_parts)
      |> Enum.intersperse(0)

    :crypto.hash(:sha256, data)
  end

  def get_or_create_asset(db, execution_id, type, path, blob_key, size, metadata) do
    with_transaction(db, fn ->
      hash = hash_asset(type, path, blob_key, metadata)
      now = current_timestamp()

      {:ok, asset_id} =
        case query_one(db, "SELECT id FROM assets WHERE hash = ?1", {hash}) do
          {:ok, {asset_id}} ->
            {:ok, asset_id}

          {:ok, nil} ->
            {:ok, blob_id} = Values.get_or_create_blob(db, blob_key, size)

            {:ok, asset_id} =
              insert_one(db, :assets, %{
                hash: {:blob, hash},
                type: type,
                path: path,
                blob_id: blob_id
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
        end

      {:ok, _} =
        insert_one(
          db,
          :execution_assets,
          %{
            execution_id: execution_id,
            asset_id: asset_id,
            created_at: now
          },
          on_conflict: "DO NOTHING"
        )

      {:ok, asset_id}
    end)
  end

  def get_asset_by_id(db, asset_id, load_metadata) do
    case query_one(
           db,
           """
           SELECT a.type, a.path, b.key, b.size
           FROM assets AS a
           INNER JOIN blobs AS b ON b.id = a.blob_id
           WHERE a.id = ?1
           """,
           {asset_id}
         ) do
      {:ok, {type, path, blob_key, size}} ->
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

        {:ok, {type, path, blob_key, size, metadata}}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  # TODO: get all assets for run?
  def get_assets_for_execution(db, execution_id) do
    case query(
           db,
           "SELECT asset_id FROM execution_assets WHERE execution_id = ?1",
           {execution_id}
         ) do
      {:ok, rows} ->
        {:ok, Enum.map(rows, fn {asset_id} -> asset_id end)}
    end
  end

  defp insert_result(
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

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
        {:ok, value_id} = get_or_create_value(db, value)
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

  def get_checkpoint_arguments(db, checkpoint_id, load_metadata \\ false) do
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
            case get_value_by_id(db, value_id, load_metadata) do
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
            {:ok, value_id} = get_or_create_value(db, value)
            {1, nil, value_id, nil}

          {:abandoned, retry_id} ->
            {2, nil, nil, retry_id}

          :cancelled ->
            {3, nil, nil, nil}

          {:deferred, defer_id} ->
            {4, nil, nil, defer_id}
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

  def get_result(db, execution_id, load_metadata \\ false) do
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
              case get_value_by_id(db, value_id, load_metadata) do
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

  def get_value_by_id(db, value_id, load_metadata) do
    case query_one!(
           db,
           "SELECT format, content, blob_key FROM values_ WHERE id = ?1",
           {value_id}
         ) do
      {:ok, {format, content, blob_key}} ->
        references =
          case query(
                 db,
                 "SELECT number, reference_id FROM value_references WHERE value_id = ?1",
                 {value_id}
               ) do
            {:ok, rows} -> Map.new(rows)
          end

        metadata =
          if load_metadata do
            case query(
                   db,
                   "SELECT key, value FROM value_metadata WHERE value_id = ?1",
                   {value_id}
                 ) do
              {:ok, rows} ->
                Map.new(rows, fn {k, v} -> {k, Jason.decode!(v)} end)
            end
          end

        value =
          case {content, blob_key} do
            {content, nil} ->
              {:raw, format, content, references, metadata}

            {nil, blob_key} ->
              {:blob, format, blob_key, references, metadata}
          end

        {:ok, value}
    end
  end

  defp hash_value(format, content, blob_key, metadata, references) do
    metadata_parts =
      metadata
      |> Enum.sort()
      |> Enum.flat_map(fn {k, v} -> [k, Jason.encode!(v)] end)

    references_parts =
      references
      |> Enum.sort()
      |> Enum.flat_map(fn {k, v} -> [Integer.to_string(k), Integer.to_string(v)] end)

    parts = [format, content || 0, blob_key || 0, references_parts, metadata_parts]
    :crypto.hash(:sha256, Enum.intersperse(parts, 0))
  end

  def get_or_create_value(db, value) do
    {format, content, blob_key, references, metadata} =
      case value do
        {:raw, format, content, references, metadata} ->
          {format, content, nil, references, metadata}

        {:blob, format, blob_key, references, metadata} ->
          {format, nil, blob_key, references, metadata}
      end

    hash = hash_value(format, content, blob_key, metadata, references)

    # TODO: don't assume hash is unique?
    case query_one(db, "SELECT id FROM values_ WHERE hash = ?1", {hash}) do
      {:ok, {id}} ->
        {:ok, id}

      {:ok, nil} ->
        {:ok, value_id} =
          insert_one(db, :values_, %{
            hash: hash,
            format: format,
            content: content,
            blob_key: blob_key
          })

        {:ok, _} =
          insert_many(
            db,
            :value_references,
            {:value_id, :number, :reference_id},
            Enum.map(references, fn {number, reference_id} ->
              {value_id, number, reference_id}
            end)
          )

        {:ok, _} =
          insert_many(
            db,
            :value_metadata,
            {:value_id, :key, :value},
            Enum.map(metadata, fn {k, v} ->
              {value_id, k, Jason.encode!(v)}
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

    # TODO: don't assume hash is unique?
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

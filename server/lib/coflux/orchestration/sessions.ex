defmodule Coflux.Orchestration.Sessions do
  import Coflux.Store

  def start_session(db) do
    with_transaction(db, fn ->
      case generate_external_id(db, :sessions, 30) do
        {:ok, external_id} ->
          case insert_one(db, :sessions, %{
                 external_id: external_id,
                 created_at: current_timestamp()
               }) do
            {:ok, session_id} ->
              {:ok, session_id, external_id}
          end
      end
    end)
  end

  defp insert_manifest(db, repository, targets, targets_hash) do
    {:ok, manifest_id} =
      insert_one(db, :manifests, %{
        repository: repository,
        targets_hash: targets_hash
      })

    {:ok, target_ids} =
      insert_many(
        db,
        :targets,
        {:manifest_id, :name, :type},
        Enum.map(targets, fn {name, data} ->
          type =
            case data.type do
              :workflow -> 0
              :task -> 1
              :sensor -> 2
            end

          {manifest_id, name, type}
        end)
      )

    {:ok, _} =
      insert_many(
        db,
        :parameters,
        {:target_id, :name, :position, :default_, :annotation},
        targets
        |> Enum.zip(target_ids)
        |> Enum.flat_map(fn {{_, data}, target_id} ->
          data.parameters
          |> Enum.with_index()
          |> Enum.map(fn {{name, default, annotation}, index} ->
            {target_id, name, index, default, annotation}
          end)
        end)
      )

    {:ok, manifest_id}
  end

  def get_or_create_manifest(db, repository, targets) do
    targets = Enum.sort_by(targets, fn {name, _} -> name end)
    targets_hash = :erlang.phash2(targets)

    with_transaction(db, fn ->
      case query_one(
             db,
             """
             SELECT id
             FROM manifests
             WHERE repository = ?1 AND targets_hash = ?2
             """,
             {repository, targets_hash}
           ) do
        {:ok, nil} ->
          insert_manifest(db, repository, targets, targets_hash)

        {:ok, {manifest_id}} ->
          {:ok, manifest_id}
      end
    end)
  end

  def record_session_manifest(db, session_id, manifest_id) do
    with_transaction(db, fn ->
      now = current_timestamp()

      {:ok, _} =
        insert_one(db, :session_manifests, %{
          session_id: session_id,
          manifest_id: manifest_id,
          created_at: now
        })

      :ok
    end)
  end

  def get_latest_targets(db) do
    # TODO: reduce number of queries

    {:ok, manifests} =
      query(
        db,
        """
        SELECT id, repository
        FROM (
          SELECT m.id, m.repository
          FROM manifests AS m
          INNER JOIN session_manifests AS sm ON sm.manifest_id = m.id
          ORDER BY m.repository, sm.created_at DESC
        )
        GROUP BY repository
        """
      )

    targets =
      Map.new(manifests, fn {manifest_id, repository} ->
        {:ok, rows} =
          query(
            db,
            """
            SELECT id, name, type
            FROM targets
            WHERE manifest_id = ?1
            """,
            {manifest_id}
          )

        {repository,
         Map.new(rows, fn {target_id, target, type} ->
           {:ok, parameters} =
             query(
               db,
               """
               SELECT name, default_, annotation
               FROM parameters
               WHERE target_id = ?1
               ORDER BY position
               """,
               {target_id}
             )

           type =
             case type do
               0 -> :workflow
               1 -> :task
               2 -> :sensor
             end

           {target, %{type: type, parameters: parameters}}
         end)}
      end)

    {:ok, targets}
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end

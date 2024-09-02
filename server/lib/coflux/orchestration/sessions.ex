defmodule Coflux.Orchestration.Sessions do
  import Coflux.Store

  def start_session(db, environment_id) do
    with_transaction(db, fn ->
      case generate_external_id(db, :sessions, 30) do
        {:ok, external_id} ->
          case insert_one(db, :sessions, %{
                 environment_id: environment_id,
                 external_id: external_id,
                 created_at: current_timestamp()
               }) do
            {:ok, session_id} ->
              {:ok, session_id, external_id, environment_id}
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
        :target_parameters,
        {:target_id, :position, :name, :default_, :annotation},
        targets
        |> Enum.zip(target_ids)
        |> Enum.flat_map(fn {{_, data}, target_id} ->
          data.parameters
          |> Enum.with_index()
          |> Enum.map(fn {{name, default, annotation}, index} ->
            {target_id, index, name, default, annotation}
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

  def get_target(db, repository, target_name, environment_id) do
    case query_one(
           db,
           """
           SELECT t.id, t.type
           FROM targets AS t
           INNER JOIN manifests AS m ON m.id = t.manifest_id
           INNER JOIN session_manifests AS sm ON sm.manifest_id = m.id
           INNER JOIN sessions AS s ON s.id = sm.session_id
           WHERE
             m.repository = ?1 AND
             t.name = ?2 AND
             s.environment_id = ?3
           ORDER BY sm.created_at DESC
           LIMIT 1
           """,
           {repository, target_name, environment_id}
         ) do
      {:ok, {target_id, type}} ->
        {:ok, parameters} = get_target_parameters(db, target_id)
        {:ok, build_target(type, parameters)}

      {:ok, nil} ->
        {:ok, nil}
    end
  end

  defp get_target_parameters(db, target_id) do
    query(
      db,
      """
      SELECT name, default_, annotation
      FROM target_parameters
      WHERE target_id = ?1
      ORDER BY position
      """,
      {target_id}
    )
  end

  defp build_target(type, parameters) do
    type =
      case type do
        0 -> :workflow
        1 -> :task
        2 -> :sensor
      end

    %{type: type, parameters: parameters}
  end

  def get_latest_targets(db, environment_id) do
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
          INNER JOIN sessions AS s ON s.id = sm.session_id
          WHERE s.environment_id = ?1
          ORDER BY m.repository, sm.created_at DESC
        )
        GROUP BY repository
        """,
        {environment_id}
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
           {:ok, parameters} = get_target_parameters(db, target_id)
           {target, build_target(type, parameters)}
         end)}
      end)

    {:ok, targets}
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end

defmodule Coflux.Orchestration.Launches do
  import Coflux.Store

  def create_launch(db, pool_id) do
    insert_one(db, :launches, %{
      pool_id: pool_id,
      created_at: current_timestamp()
    })
  end

  def create_launch_result(db, launch_id, status) do
    insert_one(db, :launch_results, %{
      launch_id: launch_id,
      status: status,
      created_at: current_timestamp()
    })
  end

  def get_latest_launches(db, timeout_ms \\ 60_000) do
    launched_since = current_timestamp() - timeout_ms

    case query(
           db,
           """
           SELECT pool_id, MAX(created_at)
           FROM launches
           WHERE created_at >= ?1
           GROUP BY pool_id
           """,
           {launched_since}
         ) do
      {:ok, rows} ->
        {:ok, Map.new(rows)}
    end
  end

  def get_pending_launches(db, timeout_ms \\ 60_000) do
    launched_since = current_timestamp() - timeout_ms

    query(
      db,
      """
      SELECT l.id, l.pool_id, p.name, r.status
      FROM launches AS l
      INNER JOIN pools AS p ON p.id = l.pool_id
      LEFT JOIN launch_results AS r ON r.launch_id = l.id
      LEFT JOIN sessions AS s ON s.launch_id = l.id
      WHERE l.created_at >= ?1 AND s.id IS NULL
      """,
      {launched_since}
    )
  end

  def get_launch_by_id(db, launch_id) do
    query_one(
      db,
      """
      SELECT p.id, p.environment_id
      FROM launches AS l
      INNER JOIN pools AS p ON p.id = l.pool_id
      WHERE l.id = ?1
      """,
      {launch_id}
    )
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end
end

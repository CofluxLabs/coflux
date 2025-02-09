defmodule Coflux.Orchestration.Launches do
  import Coflux.Store

  def create_launch(db, pool_id) do
    now = current_timestamp()

    case insert_one(db, :launches, %{
           pool_id: pool_id,
           created_at: now
         }) do
      {:ok, launch_id} ->
        {:ok, launch_id, now}
    end
  end

  def create_launch_result(db, launch_id, data, error) do
    now = current_timestamp()

    case insert_one(db, :launch_results, %{
           launch_id: launch_id,
           # status: status,
           data: if(data, do: :erlang.term_to_binary(data)),
           error: if(error, do: Jason.encode!(error)),
           created_at: now
         }) do
      {:ok, _} ->
        {:ok, now}
    end
  end

  def create_launch_state(db, launch_id, state) do
    case insert_one(db, :launch_states, %{
           launch_id: launch_id,
           state: encode_state(state),
           created_at: current_timestamp()
         }) do
      {:ok, _} -> :ok
    end
  end

  def create_launch_stop(db, launch_id) do
    now = current_timestamp()

    case insert_one(db, :launch_stops, %{
           launch_id: launch_id,
           created_at: now
         }) do
      {:ok, launch_stop_id} -> {:ok, launch_stop_id, now}
    end
  end

  def create_launch_stop_result(db, launch_stop_id, error) do
    now = current_timestamp()

    case insert_one(db, :launch_stop_results, %{
           launch_stop_id: launch_stop_id,
           error: if(error, do: Jason.encode!(error)),
           created_at: now
         }) do
      {:ok, _} -> {:ok, now}
    end
  end

  def create_launch_deactivation(db, launch_id) do
    now = current_timestamp()

    case insert_one(db, :launch_deactivations, %{
           launch_id: launch_id,
           created_at: now
         }) do
      {:ok, _} ->
        {:ok, now}
    end
  end

  def get_active_launches(db) do
    case query(
           db,
           """
           SELECT
             l.id,
             l.created_at,
             p.id,
             p.name,
             p.environment_id,
             pd.launcher_id,
             (SELECT ls.state
               FROM launch_states AS ls
               WHERE ls.launch_id = l.id
               ORDER BY ls.created_at DESC
               LIMIT 1) AS state,
             r.data
           FROM launches AS l
           INNER JOIN pools AS p ON p.id = l.pool_id
           INNER JOIN pool_definitions AS pd ON pd.id = p.pool_definition_id
           LEFT JOIN launch_results AS r ON r.launch_id = l.id
           LEFT JOIN launch_stops AS s ON s.id = (
             SELECT id
             FROM launch_stops
             WHERE launch_id = l.id
             ORDER BY created_at DESC
             LIMIT 1
           )
           LEFT JOIN launch_stop_results AS sr ON sr.launch_stop_id = s.id
           LEFT JOIN launch_deactivations AS d ON d.launch_id = l.id
           WHERE d.created_at IS NULL
           ORDER BY l.created_at DESC
           """
         ) do
      {:ok, rows} ->
        {:ok,
         Enum.map(
           rows,
           fn {launch_id, created_at, pool_id, pool_name, environment_id, launcher_id, state,
               data} ->
             {launch_id, created_at, pool_id, pool_name, environment_id, launcher_id,
              decode_state(state), if(data, do: :erlang.binary_to_term(data))}
           end
         )}
    end
  end

  def get_pool_launches(db, pool_name, limit \\ 100) do
    # TODO: decode errors?
    query(
      db,
      """
      SELECT l.id, pd.launcher_id, l.created_at, r.created_at, r.error, s.created_at, sr.created_at, sr.error, d.created_at
      FROM launches AS l
      INNER JOIN pools AS p ON p.id = l.pool_id
      INNER JOIN pool_definitions AS pd ON pd.id = p.pool_definition_id
      LEFT JOIN launch_results AS r ON r.launch_id = l.id
      LEFT JOIN launch_stops AS s ON s.id = (
        SELECT id
        FROM launch_stops
        WHERE launch_id = l.id
        ORDER BY created_at DESC
        LIMIT 1
      )
      LEFT JOIN launch_stop_results AS sr ON sr.launch_stop_id = s.id
      LEFT JOIN launch_deactivations AS d ON d.launch_id = l.id
      WHERE p.name = ?1
      ORDER BY l.created_at DESC
      LIMIT ?2
      """,
      {pool_name, limit}
    )
  end

  defp current_timestamp() do
    System.os_time(:millisecond)
  end

  defp encode_state(state) do
    case state do
      :active -> 0
      :paused -> 1
      :draining -> 2
    end
  end

  defp decode_state(value) do
    case value do
      nil -> :active
      0 -> :active
      1 -> :paused
      2 -> :draining
    end
  end
end

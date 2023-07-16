defmodule Coflux.Store.Migrations do
  alias Exqlite.Sqlite3

  @otp_app Mix.Project.config()[:app]

  def run(db) do
    migrations_dir = Application.app_dir(@otp_app, "priv/migrations")
    setup_migrations_table(db)

    migrations_dir
    |> get_available_versions()
    |> MapSet.difference(get_migrated_versions(db))
    |> Enum.sort()
    |> Enum.each(&run_migration(db, migrations_dir, &1))

    :ok
  end

  defp get_available_versions(migrations_dir) do
    migrations_dir
    |> File.ls!()
    |> Enum.filter(&(Path.extname(&1) == ".sql"))
    |> Enum.map(&Path.basename(&1, ".sql"))
    |> Enum.map(&String.to_integer/1)
    |> MapSet.new()
  end

  defp setup_migrations_table(db) do
    :ok =
      Sqlite3.execute(
        db,
        "CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY)"
      )
  end

  defp get_migrated_versions(db) do
    {:ok, statement} = Sqlite3.prepare(db, "SELECT version FROM schema_migrations")
    {:ok, rows} = Sqlite3.fetch_all(db, statement)
    :ok = Sqlite3.release(db, statement)

    rows
    |> Enum.map(fn [version] -> version end)
    |> MapSet.new()
  end

  defp run_migration(db, migrations_dir, version) do
    sql =
      migrations_dir
      |> Path.join("#{version}.sql")
      |> File.read!()

    :ok = Sqlite3.execute(db, "BEGIN")
    :ok = Sqlite3.execute(db, sql)
    :ok = insert_schema_migration(db, version)
    :ok = Sqlite3.execute(db, "COMMIT")
  end

  defp insert_schema_migration(db, version) do
    {:ok, statement} = Sqlite3.prepare(db, "INSERT INTO schema_migrations (version) VALUES (?1)")
    :ok = Sqlite3.bind(db, statement, [version])
    :done = Sqlite3.step(db, statement)
    Sqlite3.release(db, statement)
  end
end

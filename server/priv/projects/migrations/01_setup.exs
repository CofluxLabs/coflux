defmodule Coflux.Repo.Projects.Migrations.Setup do
  use Ecto.Migration

  defp create_notify_trigger(table) do
    execute(
      "CREATE TRIGGER #{table}_insert AFTER INSERT ON #{prefix()}.#{table} FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER #{table}_insert ON #{prefix()}.#{table}"
    )
  end

  def change do
    execute(
      """
      CREATE FUNCTION notify_insert()
      RETURNS trigger AS $$
      BEGIN
        PERFORM pg_notify('insert', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ':' || row_to_json(NEW));
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION notify_insert()"
    )

    create table("tasks") do
      add :repository, :string, null: false
      add :version, :string, null: false
      add :target, :string, null: false
      add :parameters, {:array, :map}, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index("tasks", [:repository, :version, :target])

    create_notify_trigger("tasks")

    create table("runs", primary_key: false) do
      add :id, :bytea, null: false, primary_key: true
      add :task_id, references("tasks", on_delete: :delete_all), null: false
      add :tags, {:array, :string}, null: false
      add :idempotency_key, :string
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index("runs", [:idempotency_key])

    create_notify_trigger("runs")

    create table("steps", primary_key: false) do
      add :run_id, references("runs", type: :bytea, on_delete: :delete_all), null: false, primary_key: true
      add :id, :bytea, null: false, primary_key: true
      add :repository, :string, null: false
      add :target, :string, null: false
      add :arguments, {:array, :string}, null: false
      add :tags, {:array, :string}, null: false
      add :priority, :integer, null: false
      add :cache_key, :string
      add :cached_run_id, :bytea
      add :cached_step_id, references("steps", column: :id, type: :bytea, on_delete: :nilify_all, with: [cached_run_id: :run_id])
      add :created_at, :utc_datetime_usec, null: false
    end

    create index("steps", [:cache_key])

    create_notify_trigger("steps")

    create table("executions") do
      add :repository, :string, null: false
      add :target, :string, null: false
      add :arguments, {:array, :string}, null: false
      add :tags, {:array, :string}, null: false
      add :priority, :integer, null: false
      add :version, :string
      add :execute_after, :utc_datetime
      add :created_at, :utc_datetime_usec, null: false
    end

    create_notify_trigger("executions")

    create table("attempts", primary_key: false) do
      add :run_id, :bytea, null: false, primary_key: true
      add :step_id, references("steps", type: :bytea, on_delete: :delete_all, with: [run_id: :run_id]), null: false, primary_key: true
      add :number, :smallint, null: false, primary_key: true
      add :execution_id, references("executions", type: :uuid, on_delete: :delete_all), null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create_notify_trigger("attempts")

    alter table("steps") do
      add :parent_step_id, :bytea
      add :parent_attempt, references("attempts", column: :number, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, parent_step_id: :step_id])
    end

    create table("assignments", primary_key: false) do
      add :execution_id, :uuid, null: false, primary_key: true
      add :created_at, :utc_datetime_usec, null: false
    end

    create_notify_trigger("assignments")

    create table("heartbeats", primary_key: false) do
      add :execution_id, :uuid, null: false, primary_key: true
      add :created_at, :utc_datetime_usec, null: false, primary_key: true
      add :status, :smallint
    end

    create_notify_trigger("heartbeats")

    create table("results", primary_key: false) do
      add :execution_id, :uuid, null: false, primary_key: true
      add :type, :smallint, null: false
      add :value, :string
      add :extra, :map
      add :created_at, :utc_datetime_usec, null: false
    end

    create_notify_trigger("results")

    create table("dependencies", primary_key: false) do
      add :execution_id, :uuid, null: false, primary_key: true
      add :dependency_id, :uuid, null: false, primary_key: true
      add :created_at, :utc_datetime_usec, null: false
    end

    create_notify_trigger("dependencies")
  end
end

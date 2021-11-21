defmodule Coflux.Repo.Projects.Migrations.CreateDependencies do
  use Ecto.Migration

  def change do
    create table("dependencies", primary_key: false) do
      add :run_id, :bytea, null: false, primary_key: true
      add :step_id, :bytea, null: false, primary_key: true
      add :attempt, references("executions", column: :attempt, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, step_id: :step_id]), null: false, primary_key: true
      add :dependency_run_id, :bytea, null: false, primary_key: true
      add :dependency_step_id, :bytea, null: false, primary_key: true
      add :dependency_attempt, references("executions", column: :attempt, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, step_id: :step_id]), null: false, primary_key: true
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER dependencies_insert AFTER INSERT ON #{prefix()}.dependencies FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER dependencies_insert ON #{prefix()}.dependencies"
    )
  end
end

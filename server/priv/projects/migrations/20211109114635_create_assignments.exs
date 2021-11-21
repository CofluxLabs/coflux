defmodule Coflux.Repo.Projects.Migrations.CreateAssignments do
  use Ecto.Migration

  def change do
    create table("assignments", primary_key: false) do
      add :run_id, :bytea, null: false, primary_key: true
      add :step_id, :bytea, null: false, primary_key: true
      add :attempt, references("executions", column: :attempt, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, step_id: :step_id]), null: false, primary_key: true
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER assignments_insert AFTER INSERT ON #{prefix()}.assignments FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER assignments_insert ON #{prefix()}.assignments"
    )
  end
end

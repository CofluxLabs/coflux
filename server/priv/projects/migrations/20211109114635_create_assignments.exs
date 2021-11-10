defmodule Coflux.Repo.Projects.Migrations.CreateAssignments do
  use Ecto.Migration

  def change do
    create table("assignments", primary_key: false) do
      add :execution_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :created_at, :utc_datetime, null: false
    end

    execute(
      "CREATE TRIGGER assignments_insert AFTER INSERT ON #{prefix()}.assignments FOR EACH ROW EXECUTE FUNCTION notify_insert('execution_id')",
      "DROP TRIGGER assignments_insert ON #{prefix()}.assignments"
    )
  end
end

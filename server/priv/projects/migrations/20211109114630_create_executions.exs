defmodule Coflux.Repo.Projects.Migrations.CreateExecutions do
  use Ecto.Migration

  def change do
    create table("executions") do
      add :step_id, references("steps", on_delete: :delete_all), null: false
      add :version, :string
      add :execute_after, :utc_datetime
      add :created_at, :utc_datetime, null: false
    end

    alter table("steps") do
      add :parent_id, references("executions", on_delete: :delete_all)
    end

    execute(
      "CREATE TRIGGER executions_insert AFTER INSERT ON #{prefix()}.executions FOR EACH ROW EXECUTE FUNCTION notify_insert('id')",
      "DROP TRIGGER executions_insert ON #{prefix()}.executions"
    )
  end
end

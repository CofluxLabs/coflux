defmodule Coflux.Repo.Projects.Migrations.CreateExecutions do
  use Ecto.Migration

  def change do
    create table("executions", primary_key: false) do
      add :run_id, :bytea, null: false, primary_key: true
      add :step_id, references("steps", type: :bytea, on_delete: :delete_all, with: [run_id: :run_id]), null: false, primary_key: true
      add :attempt, :smallint, null: false, primary_key: true
      add :version, :string
      add :execute_after, :utc_datetime
      add :created_at, :utc_datetime_usec, null: false
    end

    alter table("steps") do
      add :parent_step_id, :bytea
      add :parent_attempt, references("executions", column: :attempt, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, parent_step_id: :step_id])
    end

    execute(
      "CREATE TRIGGER executions_insert AFTER INSERT ON #{prefix()}.executions FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER executions_insert ON #{prefix()}.executions"
    )
  end
end

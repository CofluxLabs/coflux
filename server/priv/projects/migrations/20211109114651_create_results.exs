defmodule Coflux.Repo.Projects.Migrations.CreateResults do
  use Ecto.Migration

  def change do
    create table("results", primary_key: false) do
      add :run_id, :bytea, null: false, primary_key: true
      add :step_id, :bytea, null: false, primary_key: true
      add :attempt, references("executions", column: :attempt, type: :smallint, on_delete: :delete_all, with: [run_id: :run_id, step_id: :step_id]), null: false, primary_key: true
      add :type, :integer, null: false
      add :value, :string
      add :extra, :map
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER results_insert AFTER INSERT ON #{prefix()}.results FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER results_insert ON #{prefix()}.results"
    )
  end
end

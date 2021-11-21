defmodule Coflux.Repo.Projects.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table("runs", primary_key: false) do
      add :id, :bytea, null: false, primary_key: true
      add :task_id, references("tasks", on_delete: :delete_all), null: false
      add :tags, {:array, :string}, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER runs_insert AFTER INSERT ON #{prefix()}.runs FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER runs_insert ON #{prefix()}.runs"
    )
  end
end

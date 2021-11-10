defmodule Coflux.Repo.Projects.Migrations.CreateRuns do
  use Ecto.Migration

  def change do
    create table("runs") do
      add :task_id, references("tasks", on_delete: :delete_all), null: false
      add :tags, {:array, :string}, null: false
    end

    execute(
      "CREATE TRIGGER runs_insert AFTER INSERT ON #{prefix()}.runs FOR EACH ROW EXECUTE FUNCTION notify_insert('id')",
      "DROP TRIGGER runs_insert ON #{prefix()}.runs"
    )
  end
end

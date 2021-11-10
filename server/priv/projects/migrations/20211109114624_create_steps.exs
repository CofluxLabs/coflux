defmodule Coflux.Repo.Projects.Migrations.CreateSteps do
  use Ecto.Migration

  def change do
    create table("steps") do
      add :run_id, references("runs", on_delete: :delete_all), null: false
      add :repository, :string, null: false
      add :target, :string, null: false
      add :tags, {:array, :string}, null: false
      add :priority, :integer, null: false
      add :created_at, :utc_datetime, null: false
    end

    execute(
      "CREATE TRIGGER steps_insert AFTER INSERT ON #{prefix()}.steps FOR EACH ROW EXECUTE FUNCTION notify_insert('id')",
      "DROP TRIGGER steps_insert ON #{prefix()}.steps"
    )
  end
end

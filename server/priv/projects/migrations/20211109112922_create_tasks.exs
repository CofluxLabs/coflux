defmodule Coflux.Repo.Projects.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table("tasks") do
      add :repository, :string, null: false
      add :version, :string, null: false
      add :target, :string, null: false
      add :parameters, {:array, :map}, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index("tasks", [:repository, :version, :target])

    execute(
      "CREATE TRIGGER tasks_insert AFTER INSERT ON #{prefix()}.tasks FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER tasks_insert ON #{prefix()}.tasks"
    )
  end
end

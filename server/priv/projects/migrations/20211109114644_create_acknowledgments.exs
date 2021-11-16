defmodule Coflux.Repo.Projects.Migrations.CreateAcknowledgments do
  use Ecto.Migration

  def change do
    create table("acknowledgments") do
      add :execution_id, references("executions", on_delete: :delete_all), null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER acknowledgments_insert AFTER INSERT ON #{prefix()}.acknowledgments FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER acknowledgments_insert ON #{prefix()}.acknowledgments"
    )
  end
end

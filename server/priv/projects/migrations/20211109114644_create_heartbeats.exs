defmodule Coflux.Repo.Projects.Migrations.CreateHeartbeats do
  use Ecto.Migration

  def change do
    create table("heartbeats", primary_key: false) do
      add :execution_id, references("executions", on_delete: :delete_all), null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER heartbeats_insert AFTER INSERT ON #{prefix()}.heartbeats FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER heartbeats_insert ON #{prefix()}.heartbeats"
    )
  end
end

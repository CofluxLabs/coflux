defmodule Coflux.Repo.Projects.Migrations.CreateResults do
  use Ecto.Migration

  def change do
    create table("results", primary_key: false) do
      add :execution_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :type, :integer, null: false
      add :value, :text
      add :extra, :map
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER results_insert AFTER INSERT ON #{prefix()}.results FOR EACH ROW EXECUTE FUNCTION notify_insert('execution_id')",
      "DROP TRIGGER results_insert ON #{prefix()}.results"
    )
  end
end

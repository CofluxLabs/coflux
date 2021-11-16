defmodule Coflux.Repo.Projects.Migrations.CreateDependencies do
  use Ecto.Migration

  def change do
    create table("dependencies", primary_key: false) do
      add :execution_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :dependency_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    execute(
      "CREATE TRIGGER dependencies_insert AFTER INSERT ON #{prefix()}.dependencies FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER dependencies_insert ON #{prefix()}.dependencies"
    )
  end
end

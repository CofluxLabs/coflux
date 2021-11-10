defmodule Coflux.Repo.Projects.Migrations.CreateDependencies do
  use Ecto.Migration

  def change do
    create table("dependencies", primary_key: false) do
      add :execution_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :dependency_id, references("executions", on_delete: :delete_all), primary_key: true, null: false
      add :created_at, :utc_datetime, null: false
    end

    execute(
      "CREATE TRIGGER dependencies_insert AFTER INSERT ON #{prefix()}.dependencies EXECUTE FUNCTION notify_insert('execution_id')",
      "DROP TRIGGER dependencies_insert ON #{prefix()}.dependencies"
    )
  end
end

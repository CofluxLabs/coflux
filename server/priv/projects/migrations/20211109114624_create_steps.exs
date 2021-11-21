defmodule Coflux.Repo.Projects.Migrations.CreateSteps do
  use Ecto.Migration

  def change do
    create table("steps", primary_key: false) do
      add :run_id, references("runs", type: :bytea, on_delete: :delete_all), null: false, primary_key: true
      add :id, :bytea, null: false, primary_key: true
      add :repository, :string, null: false
      add :target, :string, null: false
      add :arguments, {:array, :string}, null: false
      add :tags, {:array, :string}, null: false
      add :priority, :integer, null: false
      add :cache_key, :string
      add :cached_run_id, :bytea
      add :cached_step_id, references("steps", column: :id, type: :bytea, on_delete: :nilify_all, with: [cached_run_id: :run_id])
      add :created_at, :utc_datetime_usec, null: false
    end

    create index("steps", [:cache_key])

    execute(
      "CREATE TRIGGER steps_insert AFTER INSERT ON #{prefix()}.steps FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER steps_insert ON #{prefix()}.steps"
    )
  end
end

defmodule Coflux.Repo.Projects.Migrations.CreateSteps do
  use Ecto.Migration

  def change do
    create table("steps") do
      add :run_id, references("runs", on_delete: :delete_all), null: false
      add :repository, :string, null: false
      add :target, :string, null: false
      add :arguments, {:array, :string}, null: false
      add :tags, {:array, :string}, null: false
      add :priority, :integer, null: false
      add :cache_key, :string
      add :cached_step_id, references("steps", on_delete: :nilify_all)
      add :created_at, :utc_datetime_usec, null: false
    end

    create index("steps", [:cache_key])

    execute(
      "CREATE TRIGGER steps_insert AFTER INSERT ON #{prefix()}.steps FOR EACH ROW EXECUTE FUNCTION notify_insert()",
      "DROP TRIGGER steps_insert ON #{prefix()}.steps"
    )
  end
end

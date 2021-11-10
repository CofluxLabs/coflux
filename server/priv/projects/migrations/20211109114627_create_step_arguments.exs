defmodule Coflux.Repo.Projects.Migrations.CreateStepArguments do
  use Ecto.Migration

  def change do
    create table("step_arguments", primary_key: false) do
      add :step_id, references("steps", on_delete: :delete_all), primary_key: true
      add :index, :integer, primary_key: true
      add :type, :integer, null: false
      add :value, :text, null: false
    end
  end
end

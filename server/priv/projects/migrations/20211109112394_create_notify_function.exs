defmodule Coflux.Repo.Projects.Migrations.CreateNotifyFunction do
  use Ecto.Migration

  @execute_up """
  CREATE FUNCTION notify_insert()
  RETURNS trigger AS $$
  BEGIN
    PERFORM pg_notify('insert', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME || ':' || (row_to_json(NEW)));
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;
  """

  @execute_down """
  DROP FUNCTION notify_insert();
  """

  def change do
    execute @execute_up, @execute_down
  end
end

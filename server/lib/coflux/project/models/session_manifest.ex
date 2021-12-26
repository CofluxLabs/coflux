defmodule Coflux.Project.Models.SessionManifest do
  use Coflux.Project.Model

  @primary_key false
  schema "session_manifests" do
    belongs_to :session, Models.Session, type: :binary_id, primary_key: true
    belongs_to :manifest, Models.Manifest, primary_key: true
    field :created_at, :utc_datetime_usec
  end
end

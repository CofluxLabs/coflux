import Config

config :coflux,
  ecto_repos: [Coflux.Repo.Projects]

config :coflux, Coflux.Repo.Projects,
  migration_primary_key: [type: :binary_id]

import_config "#{config_env()}.exs"

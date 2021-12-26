import Config

config :coflux,
  ecto_repos: [Coflux.Repo.Projects]

import_config "#{config_env()}.exs"

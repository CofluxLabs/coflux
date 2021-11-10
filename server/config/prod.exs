import Config

config :logger, level: :info

config :coflux, Coflux.Repo.Projects,
  url: System.fetch_env!("PROJECTS_DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

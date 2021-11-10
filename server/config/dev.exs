import Config

config :logger, :console, format: "[$level] $message\n"

config :coflux, Coflux.Repo.Projects,
  hostname: "postgres",
  username: "postgres",
  password: "postgres",
  database: "projects_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  log: false

import Config

config :logger, level: :warn

config :coflux, Coflux.Repo.Projects,
  hostname: "postgres",
  username: "postgres",
  password: "postgres",
  database: "projects_test",
  pool: Ecto.Adapters.SQL.Sandbox

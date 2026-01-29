import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :langler, Langler.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("PGHOST", "localhost"),
  database: "langler_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :langler, LanglerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "K4/iHmc3VyMWrsT6ZqCigobJwLXRH8NFO2BgzdaOBfgJbSyVEbfgiVgLmAfOg+K8",
  server: false

# In test we don't send emails
config :langler, Langler.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :langler, Oban,
  testing: :inline,
  queues: false

config :langler, Langler.Content.Readability, use_nif: false

config :langler, Langler.External.Dictionary.CacheLoader, enabled: false

config :langler, :study_live_async_fetch_enabled, false

config :appsignal, :config, active: false

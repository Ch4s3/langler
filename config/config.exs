# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :langler, :scopes,
  user: [
    default: true,
    module: Langler.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Langler.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :langler,
  ecto_repos: [Langler.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :langler, LanglerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LanglerWeb.ErrorHTML, json: LanglerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Langler.PubSub,
  live_view: [signing_salt: "wOEkjjG2"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :langler, Langler.Mailer, adapter: Swoosh.Adapters.Local

config :langler, Oban,
  repo: Langler.Repo,
  engine: Oban.Engines.Basic,
  queues: [default: 50, ingestion: 10],
  plugins: [Oban.Plugins.Pruner]

config :langler, Langler.External.Dictionary.Wiktionary,
  base_url: "https://en.wiktionary.org/wiki",
  cache_table: :wiktionary_cache

config :langler, Langler.External.Dictionary.Google,
  endpoint: "https://translation.googleapis.com/language/translate/v2",
  rate_limit_per_minute: 60,
  api_key: :runtime_env

config :langler, Langler.Study.FSRS.Params,
  weights: [
    0.40255,
    1.18385,
    3.173,
    15.69105,
    7.1949,
    0.5345,
    1.4604,
    0.0046,
    1.54575,
    0.1192,
    1.01925,
    1.9395,
    0.11,
    0.29605,
    2.2698,
    0.2315,
    2.9898,
    0.51655,
    0.6621
  ],
  desired_retention: 0.9,
  learning_steps: [1.0, 10.0],
  relearning_steps: [10.0],
  maximum_interval: 36_500,
  enable_fuzzing: true

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  langler: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  langler: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

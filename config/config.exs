# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :dashboard,
  namespace: Dashboard,
  ecto_repos: [Dashboard.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :dashboard, DashboardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: DashboardWeb.ErrorHTML, json: DashboardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Dashboard.PubSub,
  live_view: [signing_salt: "2TzUMSHY"]

# Configure node/SSR rendering
config :dashboard, Dashboard.SSR.Worker,
  worker_path: "priv/static/assets/ssr/ssr_worker.js",
  runtime: "node",
  pool_size: 4

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :dashboard, Dashboard.Mailer, adapter: Swoosh.Adapters.Local

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  dashboard: [
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

# RSS Backoff configuration
config :dashboard, Dashboard.RSS.Backoff,
  # 1 hour
  default_interval: 60 * 60,
  # 5 minutes
  min_interval: 5 * 60,
  # 24 hours
  max_interval: 24 * 60 * 60,
  no_change_multiplier: 1.5,
  # 15 minutes
  error_base_interval: 15 * 60,
  # 7 days
  error_max_interval: 7 * 24 * 60 * 60,
  jitter_percent: 10

# RSS ingest dependencies
config :dashboard,
  rss_fetch_worker: Dashboard.RSS.FetchWorker,
  rss_feed_parser: Dashboard.RSS.FeedParser

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

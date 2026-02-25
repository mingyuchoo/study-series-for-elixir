# This file is responsible for configuring your playa
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your playa share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the playa.
import Config

# Configure Mix tasks and generators
config :auth,
  ecto_repos: [Auth.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :auth, Auth.Mailer, adapter: Swoosh.Adapters.Local

# Configure Mix tasks and generators
config :productivity,
  ecto_repos: [Productivity.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :productivity, Productivity.Mailer, adapter: Swoosh.Adapters.Local

# Configure Mix tasks and generators
config :playa,
  ecto_repos: [Playa.Repo]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :playa, Playa.Mailer, adapter: Swoosh.Adapters.Local

config :playa_web,
  ecto_repos: [Playa.Repo],
  generators: [context_app: :playa]

# Configures the endpoint
config :playa_web, PlayaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PlayaWeb.ErrorHTML, json: PlayaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Playa.PubSub,
  live_view: [signing_salt: "fc3C4DBK"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  playa_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../apps/playa_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.0",
  playa_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../apps/playa_web/assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Guardian authentication configuration
# The secret_key is configured in each environment file (dev.exs, test.exs, runtime.exs)
config :auth, Auth.Guardian, issuer: "auth"

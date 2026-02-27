import Config

config :discuss, Discuss.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "discuss_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :discuss_web, DiscussWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "1DYEwKRZwURUNAxbQwJ3jYg8fEFwEl65vNMiRDyHJ4ELom9uYG0QHKmAS+FMyzIR",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:discuss_web, ~w(--sourcemap=inline --watch)]},
    npx: [
      "tailwindcss",
      "--config=tailwind.config.js",
      "--input=css/app.css",
      "--output=../priv/static/assets/app.css",
      "--postcss",
      "--watch",
      cd: Path.expand("../apps/discuss_web/assets", __DIR__)
    ]
  ]

config :discuss_web, DiscussWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"apps/discuss_web/priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"apps/discuss_web/priv/gettext/.*(po)$",
      ~r"apps/discuss_web/lib/discuss_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :discuss_web, dev_routes: true

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, :debug_heex_annotations, true
config :swoosh, :api_client, false

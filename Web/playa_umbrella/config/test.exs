import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :auth, Auth.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: "playa_test#{System.get_env("MIX_TEST_PARTITION")}",
  schema: "auth",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :productivity, Productivity.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: "playa_test#{System.get_env("MIX_TEST_PARTITION")}",
  schema: "productivity",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :playa, Playa.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("DATABASE_HOST") || "localhost",
  database: "playa_test#{System.get_env("MIX_TEST_PARTITION")}",
  schema: "playa",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :playa_web, PlayaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "KzGHQU/qCUMe7RitH7NClXdBNC5Cay4y76Gk9CBMXZIba3Y+bfxYqFM4gA9CsPtT",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# In test we don't send emails.
config :playa, Playa.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Guardian secret key for testing
# This is a test-only key and should NOT be used in production
config :auth, Auth.Guardian,
  secret_key: "test_secret_key_for_guardian_in_test_environment_do_not_use_in_production"

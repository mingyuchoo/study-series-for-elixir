import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/elixir_gui_todo start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") || ElixirGuiTodo.DesktopPaths.enabled?() do
  config :elixir_gui_todo, ElixirGuiTodoWeb.Endpoint, server: true
end

config :elixir_gui_todo, ElixirGuiTodoWeb.Endpoint,
  http: [
    ip:
      if(ElixirGuiTodo.DesktopPaths.enabled?(),
        do: {127, 0, 0, 1},
        else: {0, 0, 0, 0, 0, 0, 0, 0}
      ),
    port: String.to_integer(System.get_env("PORT", "4000"))
  ]

if config_env() == :prod do
  database_path =
    if ElixirGuiTodo.DesktopPaths.enabled?() do
      ElixirGuiTodo.DesktopPaths.database_path()
    else
      System.get_env("DATABASE_PATH")
    end ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/elixir_gui_todo/elixir_gui_todo.db
      """

  config :elixir_gui_todo, ElixirGuiTodo.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    if ElixirGuiTodo.DesktopPaths.enabled?() do
      ElixirGuiTodo.DesktopPaths.secret_key_base()
    else
      System.get_env("SECRET_KEY_BASE")
    end ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :elixir_gui_todo, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :elixir_gui_todo, ElixirGuiTodoWeb.Endpoint,
    url: [
      host: if(ElixirGuiTodo.DesktopPaths.enabled?(), do: "127.0.0.1", else: host),
      port: String.to_integer(System.get_env("PORT", "4000")),
      scheme: if(ElixirGuiTodo.DesktopPaths.enabled?(), do: "http", else: "https")
    ],
    http: [
      ip:
        if(ElixirGuiTodo.DesktopPaths.enabled?(),
          do: {127, 0, 0, 1},
          else: {0, 0, 0, 0, 0, 0, 0, 0}
        ),
      port: String.to_integer(System.get_env("PORT", "4000"))
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :elixir_gui_todo, ElixirGuiTodoWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :elixir_gui_todo, ElixirGuiTodoWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

defmodule ElixirGuiTodo.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_gui_todo,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ElixirGuiTodo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      # Includes the upstream Elixir 1.20 compiler deprecation fix, not yet released on Hex.
      {:phoenix_ecto,
       github: "phoenixframework/phoenix_ecto", ref: "a0c342b5a57581037974cc992a23f4f89a77b29f"},
      {:ecto_sql, "~> 3.14.0"},
      {:ecto_sqlite3, "~> 0.25.0"},
      {:phoenix_html, "~> 4.3.0"},
      {:phoenix_live_reload, "~> 1.7.0", only: :dev},
      {:phoenix_live_view, "~> 1.2.12"},
      {:lazy_html, "~> 0.1.13", only: :test},
      {:esbuild, "~> 0.10.0", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5.1", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.2.0"},
      {:telemetry_poller, "~> 1.3.0"},
      # Includes the upstream Elixir 1.20 compiler fixes, not yet released on Hex.
      {:gettext,
       github: "elixir-gettext/gettext", ref: "0006cec94a4af0f1a8785bb15e3ab401a83df885"},
      {:jason, "~> 1.4.5"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.12.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "cmd npm ci",
        "tailwind.install --if-missing",
        "esbuild.install --if-missing"
      ],
      "assets.build": ["compile", "tailwind elixir_gui_todo", "esbuild elixir_gui_todo"],
      "assets.deploy": [
        "tailwind elixir_gui_todo --minify",
        "esbuild elixir_gui_todo --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end

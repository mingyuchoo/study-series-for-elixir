defmodule Core.MixProject do
  use Mix.Project

  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Core.Application, []}
    ]
  end

  defp deps do
    [
      {:agent_domain, in_umbrella: true},
      {:ecto_sql, "~> 3.14.0"},
      {:ecto_sqlite3, "~> 0.25.0"},
      {:hnswlib, "~> 0.1.10"},
      {:nx, "~> 1.0.0"},
      {:req, "~> 0.7.5"},
      {:jason, "~> 1.4.5"},
      {:telemetry, "~> 1.4.2"},
      {:bcrypt_elixir, "~> 3.3.2"}
    ]
  end
end

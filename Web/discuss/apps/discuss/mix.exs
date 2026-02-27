defmodule Discuss.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [
        ignore_modules: [
          Discuss.Application,
          Discuss.Repo,
          Discuss.Mailer,
          Discuss.TopicsFixtures,
          Discuss.AdminFixtures,
          Discuss.DataCase
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Discuss.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:jason, "~> 1.4"},
      {:earmark, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end

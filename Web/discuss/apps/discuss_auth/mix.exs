defmodule DiscussAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss_auth,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:discuss, in_umbrella: true},
      {:pbkdf2_elixir, "~> 2.0"},
      {:ecto_sql, "~> 3.12"},
      {:jason, "~> 1.4"}
    ]
  end
end

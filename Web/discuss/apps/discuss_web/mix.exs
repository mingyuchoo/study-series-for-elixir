defmodule DiscussWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :discuss_web,
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
          DiscussWeb.Application,
          DiscussWeb.Telemetry,
          DiscussWeb.Endpoint,
          DiscussWeb.Layouts,
          DiscussWeb.CoreComponents,
          DiscussWeb.ConnCase,
          DiscussWeb.Gettext,
          DiscussWeb.TopicHTML,
          DiscussWeb.PageHTML,
          DiscussWeb.AdminUserHTML,
          DiscussWeb.UserSessionHTML,
          DiscussWeb.UserRegistrationHTML,
          DiscussWeb.UserConfirmationHTML,
          DiscussWeb.UserPasswordResetHTML,
          DiscussWeb.ErrorHTML,
          DiscussWeb.FallbackController,
          DiscussWeb.ChangesetJSON
        ]
      ]
    ]
  end

  def application do
    [
      mod: {DiscussWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:discuss, in_umbrella: true},
      {:discuss_auth, in_umbrella: true},
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.6"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.0.10"},
      {:floki, "~> 0.37.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.7"},
      {:esbuild, "~> 0.9", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.2"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.6"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["test"],
      "assets.setup": ["esbuild.install --if-missing", "cmd npm --prefix assets install"],
      "assets.build": ["cmd npm --prefix assets run build:css", "esbuild discuss_web"],
      "assets.deploy": [
        "cmd npm --prefix assets run build:css:prod",
        "esbuild discuss_web --minify",
        "phx.digest"
      ]
    ]
  end
end

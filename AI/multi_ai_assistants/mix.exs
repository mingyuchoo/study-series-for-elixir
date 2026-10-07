defmodule MultiAiAssistants.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      elixir: "~> 1.20",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      multi_ai_assistants: [
        version: "0.1.0",
        applications: [
          agent_domain: :permanent,
          core: :permanent,
          web: :permanent
        ],
        include_executables_for: [:unix, :windows],
        steps: [:assemble, :tar]
      ]
    ]
  end
end

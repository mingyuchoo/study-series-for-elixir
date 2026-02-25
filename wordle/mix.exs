defmodule WordleGame.MixProject do
  use Mix.Project

  def project do
    [
      app: :wordle_game,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  defp escript do
    [main_module: WordleGame.CLI]
  end
end

defmodule Hockey2D.MixProject do
  use Mix.Project

  def project do
    [
      app: :hockey_2d,
      version: "1.0.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [quality: ["format --check-formatted", "test"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Hockey.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:websock_adapter, "~> 0.5"},
      {:jason, "~> 1.4"}
    ]
  end
end

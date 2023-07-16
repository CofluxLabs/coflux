defmodule Coflux.MixProject do
  use Mix.Project

  def project do
    [
      app: :coflux,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Coflux.Application, []}
    ]
  end

  defp deps do
    [
      {:cowboy, "~> 2.9"},
      {:exqlite, "~> 0.13"},
      {:jason, "~> 1.4"},
      {:topical, "~> 0.1"}
    ]
  end
end

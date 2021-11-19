defmodule Coflux.MixProject do
  use Mix.Project

  def project do
    [
      app: :coflux,
      version: "0.1.0",
      elixir: "~> 1.13-rc",
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
      {:ecto_sql, "~> 3.7"},
      {:inflex, "~> 2.0"},
      {:jason, "~> 1.2"},
      {:postgrex, "~> 0.15"}
    ]
  end
end

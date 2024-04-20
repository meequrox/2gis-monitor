defmodule DoubleGisMonitor.MixProject do
  use Mix.Project

  def project do
    [
      app: :double_gis_monitor,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {DoubleGisMonitor.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17.5"},
      {:ex_gram, "~> 0.52.2"},
      {:tesla, "~> 1.9"},
      {:hackney, "~> 1.20"}
    ]
  end
end

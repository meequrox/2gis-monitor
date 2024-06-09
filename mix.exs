defmodule DoubleGisMonitor.MixProject do
  use Mix.Project

  def project do
    [
      app: :double_gis_monitor,
      version: "1.6.9",
      elixir: "~> 1.16",
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
      {:postgrex, "~> 0.18.0"},
      {:time_zone_info, "~> 0.7.3"},
      {:telegex, "~> 1.8"},
      {:logger_file_backend, "~> 0.0.14"},
      {:observer_cli, "~> 1.7", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end

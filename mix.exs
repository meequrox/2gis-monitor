defmodule DoubleGisMonitor.MixProject do
  use Mix.Project

  def project do
    [
      app: :double_gis_monitor,
      version: "1.6.14",
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
    {timezone_mod, timezone_ver} =
      case :os.type() do
        {:unix, _name} -> {:zoneinfo, "~> 0.1.8"}
        {:win32, _name} -> {:tz, "~> 0.26.5"}
      end

    [
      {timezone_mod, timezone_ver},
      {:httpoison, "~> 2.2"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18.0"},
      {:telegex, "~> 1.8"},
      {:logger_file_backend, "~> 0.0.14"},
      {:observer_cli, "~> 1.7", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end

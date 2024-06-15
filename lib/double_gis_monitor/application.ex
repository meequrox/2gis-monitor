defmodule DoubleGisMonitor.Application do
  @moduledoc """
  The main application to start a supervisor.
  """

  use Application

  require Logger

  @doc """
  Called when an application is started (usually from `Mix.Project.application/0`).
  This callback is responsible for starting its supervision tree.
  """
  @impl true
  def start(_type, _opts) do
    [city: city, layers: layers, interval: interval] =
      :double_gis_monitor
      |> Application.fetch_env!(:fetch)
      |> Keyword.take([:city, :layers, :interval])

    [timezone: tz, channel_id: channel_id] =
      :double_gis_monitor
      |> Application.fetch_env!(:dispatch)
      |> Keyword.take([:timezone, :channel_id])

    opts = %{
      env: Application.fetch_env!(:double_gis_monitor, :env),
      ecto_repos: Application.fetch_env!(:double_gis_monitor, :ecto_repos),
      interval: interval,
      stages_opts: %{
        fetch: %{city: city, layers: layers},
        process: %{interval: interval},
        dispatch: %{channel_id: channel_id, city: city, timezone: tz}
      }
    }

    Logger.info("Working directory: #{File.cwd!()}")
    Logger.info("Application options: #{inspect(opts, pretty: true)}")

    opts
    |> get_children()
    |> Supervisor.start_link(strategy: :one_for_one, name: __MODULE__.Supervisor)
  end

  defp get_children(%{env: env} = opts) when is_atom(env) do
    base = [
      get_migrator(opts),
      DoubleGisMonitor.Database.Repo
    ]

    rest =
      case env do
        :test ->
          []

        _other ->
          [
            DoubleGisMonitor.Bot.Telegram,
            DoubleGisMonitor.Pipeline.Worker,
            {DoubleGisMonitor.Pipeline.WorkerManager, opts}
          ]
      end

    base ++ rest
  end

  defp get_migrator(%{env: env, ecto_repos: repos}) when is_atom(env) and is_list(repos) do
    {Ecto.Migrator,
     repos: repos,
     skip: System.get_env("SKIP_MIGRATIONS", "false") == "true",
     log_migrator_sql: env != :prod}
  end
end

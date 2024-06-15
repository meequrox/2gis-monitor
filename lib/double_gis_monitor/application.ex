defmodule DoubleGisMonitor.Application do
  @moduledoc """
  DoubleGisMonitor application
  """

  use Application

  require Logger

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

    [skip: skip_migrations?] =
      :double_gis_monitor
      |> Application.fetch_env!(:ecto_migrations)
      |> Keyword.take([:skip])

    opts = %{
      env: Application.fetch_env!(:double_gis_monitor, :env),
      ecto: %{
        repos: Application.fetch_env!(:double_gis_monitor, :ecto_repos),
        skip_migrations: skip_migrations?
      },
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

  defp get_migrator(%{env: env, ecto: %{repos: repos, skip_migrations: skip_migrations?}})
       when is_atom(env) and is_list(repos) and is_boolean(skip_migrations?) do
    {Ecto.Migrator, repos: repos, skip: skip_migrations?, log_migrator_sql: env != :prod}
  end
end

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
  def start(_type, _args) do
    inspect_opts = [pretty: true]

    Logger.info(
      "DGM configuration:\n#{:double_gis_monitor |> Application.get_all_env() |> inspect(inspect_opts)}"
    )

    Logger.info(
      "Telegex configuration:\n#{:telegex |> Application.get_all_env() |> inspect(inspect_opts)}"
    )

    Logger.info(
      "Logger configuration:\n#{:logger |> Application.get_all_env() |> inspect(inspect_opts)}"
    )

    Logger.info("Working directory: #{File.cwd!()}")

    :double_gis_monitor
    |> Application.fetch_env!(:env)
    |> get_children()
    |> Supervisor.start_link(strategy: :one_for_one, name: __MODULE__.Supervisor)
  end

  @doc """
  This callback is called after its supervision tree has been stopped.
  """
  @impl true
  def stop(_state) do
    Logger.info("App stopped")
  end

  defp get_children(env) when is_atom(env) do
    base = [
      get_migrator(env),
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
            DoubleGisMonitor.Pipeline.WorkerManager
          ]
      end

    base ++ rest
  end

  defp get_migrator(env) do
    {Ecto.Migrator,
     repos: Application.fetch_env!(:double_gis_monitor, :ecto_repos),
     skip: System.get_env("SKIP_MIGRATIONS", "false") == "true",
     log_migrator_sql: env != :prod}
  end
end

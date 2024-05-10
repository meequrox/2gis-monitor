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
    Logger.info(
      "DGM configuration:\n#{:double_gis_monitor |> Application.get_all_env() |> inspect(pretty: true)}"
    )

    Logger.info(
      "Telegex configuration:\n#{:telegex |> Application.get_all_env() |> inspect(pretty: true)}"
    )

    Logger.info(
      "Logger configuration:\n#{:logger |> Application.get_all_env() |> inspect(pretty: true)}"
    )

    Logger.info("Working directory: #{File.cwd!()}")

    children = :double_gis_monitor |> Application.fetch_env!(:env) |> get_children()

    opts = [strategy: :one_for_one, name: __MODULE__.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  This callback is called after its supervision tree has been stopped.
  """
  @impl true
  def stop(_state) do
    Logger.info("App stopped")
  end

  defp get_children(env) when is_atom(env) do
    case env do
      :test ->
        [
          get_migrator(),
          DoubleGisMonitor.Db.Repo
        ]

      _other ->
        [
          get_migrator(),
          DoubleGisMonitor.Db.Repo,
          DoubleGisMonitor.Bot.Telegram,
          DoubleGisMonitor.WorkerManager
        ]
    end
  end

  defp get_migrator() do
    {Ecto.Migrator,
     repos: Application.fetch_env!(:double_gis_monitor, :ecto_repos),
     skip: System.get_env("SKIP_MIGRATIONS", "false") == "true",
     log_migrator_sql: true}
  end
end

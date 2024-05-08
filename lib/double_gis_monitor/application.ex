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

    Logger.info("Working directory: #{File.cwd!()}")

    children =
      case Application.fetch_env!(:double_gis_monitor, :env) do
        :test ->
          Logger.info("Using test environment. Do not add supervisor children.")

          []

        other ->
          Logger.info("Using #{other} environment. Adding supervisor children.")

          [
            DoubleGisMonitor.Db.Repo,
            DoubleGisMonitor.Bot.Telegram,
            DoubleGisMonitor.Worker
          ]
      end

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
end

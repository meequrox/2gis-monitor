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
    Logger.info("App started, cwd: #{File.cwd!()}")

    children = [
      # TODO: reenable childrens
      # DoubleGisMonitor.Db.Repo
      # {OPQ, name: :telegram_send_limiter},
      # {OPQ, name: :double_gis_poll_limiter},
      # ExGram,
      # {DoubleGisMonitor.Bot.Tg,
      #  [
      #    method: :polling,
      #    allowed_updates: ["message"],
      #    token: Application.fetch_env!(:ex_gram, :token)
      #  ]},
      # DoubleGisMonitor.Worker.Poller,
      # DoubleGisMonitor.Worker.Processor
    ]

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

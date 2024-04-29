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

    # TODO: Worker to run pipeline every $interval seconds
    # {:ok, a} = DoubleGisMonitor.Pipeline.Fetch.call()
    # {:ok, b} = DoubleGisMonitor.Pipeline.Process.call(a)
    # {:ok, c} = DoubleGisMonitor.Pipeline.Dispatch.call(b)

    children = [
      DoubleGisMonitor.Db.Repo,
      DoubleGisMonitor.Bot.Telegram
      # DoubleGisMonitor.Worker.Poller
    ]

    # TODO: Do not run children in test env

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

defmodule DoubleGisMonitor.Application do
  @moduledoc """
  The main application to start a supervisor.
  """

  use Application
  require Logger

  #############
  ## Callbacks
  #############

  @doc """
  Called when an application is started (usually from `Mix.Project.application/0`).
  This callback is responsible for starting its supervision tree.
  """
  @impl true
  def start(_type, _args) do
    Logger.info("Application started, cwd is #{File.cwd!()}")

    DoubleGisMonitor.Supervisor.start_link([])
  end

  @doc """
  This callback is called after its supervision tree has been stopped.
  """
  @impl true
  def stop(_state) do
    Logger.info("Application stopped")
  end
end

defmodule DoubleGisMonitor.Supervisor do
  @moduledoc """
  Supervisor to manage the children processes.
  """

  use Supervisor
  require Logger

  #############
  ## API
  #############

  @doc """
  Function to start the supervisor from application.
  """
  @spec start_link([]) ::
          {:ok, pid()}
          | :ignore
          | {:error, {:already_started, pid()} | {:shutdown, term()} | term()}
  def start_link([]) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  #############
  ## Callbacks
  #############

  @doc """
  Callback invoked to start the supervision tree.
  """
  @impl true
  def init([]) do
    Logger.info("Supervisor started")

    children = [
      DoubleGisMonitor.Repo,
      DoubleGisMonitor.EventPoller,
      DoubleGisMonitor.EventProcessor
      # DoubleGisMonitor.MessageDispatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

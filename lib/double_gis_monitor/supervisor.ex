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

  @impl true
  @callback init(init_arg :: term()) :: {:ok, tuple()}
  @doc """
  Callback invoked to start the supervision tree.
  """
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

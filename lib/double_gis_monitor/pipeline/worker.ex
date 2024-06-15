defmodule DoubleGisMonitor.Pipeline.Worker do
  @moduledoc """
  The worker receives commands from the manager to start the event pipeline.
  It is also responsible for notifying the manager about the results.
  """

  use GenServer

  require Logger

  alias DoubleGisMonitor.Pipeline.{Stage, WorkerManager}

  @spec child_spec() :: map()
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []}
    }
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  This function is used by the manager to send a command to the worker to start the pipeline.
  """
  @spec start_pipeline(map()) :: :ok
  def start_pipeline(opts) do
    GenServer.cast(__MODULE__, {:start, {:pipeline, opts}})
  end

  @impl true
  def init(_opts) do
    {:ok, 0}
  end

  @impl true
  def handle_call(request, from, state) do
    Logger.warning("Received unknown call from #{inspect(from)}: #{inspect(request)}")

    {:reply, {:error, "Unknown call request"}, state}
  end

  @impl true
  def handle_cast(
        {:start,
         {:pipeline, %{fetch: fetch_opts, process: process_opts, dispatch: dispatch_opts}}},
        state
      ) do
    with :ok <- Logger.info("Start pipeline"),
         {:ok, fetched} <- Stage.Fetch.run(fetch_opts),
         {:ok, processed} <- Stage.Process.run(fetched, process_opts),
         {:ok, %{update: updated, insert: inserted}} <-
           Stage.Dispatch.run(processed, dispatch_opts),
         :ok <- Logger.info("End pipeline") do
      {:ok, %{update: Enum.count(updated), insert: Enum.count(inserted)}}
    else
      {:error, error} = err ->
        Logger.error("Pipeline failed: #{inspect(error)}")
        err
    end
    |> WorkerManager.set_last_result()

    {:noreply, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("Received unknown cast: #{inspect(request)}")

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unknown info: #{inspect(msg)}")

    {:noreply, state}
  end
end

defmodule DoubleGisMonitor.Pipeline.Worker do
  # TODO: Create @moduledoc

  use GenServer

  require Logger

  alias DoubleGisMonitor.Pipeline.{Stage, WorkerManager}

  @spec child_spec() :: map()
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent,
      type: :worker,
      shutdown: 10_000
    }
  end

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_pipeline(map()) :: :ok
  def start_pipeline(opts) do
    GenServer.cast(__MODULE__, {:start, {:pipeline, opts}})
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{}}
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
      {:error, error} ->
        Logger.error("Pipeline failed: #{inspect(error)}")
        {:error, error}

      any ->
        Logger.error("Pipeline produced unknown result: #{inspect(any)}")
        any
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

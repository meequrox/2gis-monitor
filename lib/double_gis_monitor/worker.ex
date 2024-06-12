defmodule DoubleGisMonitor.Worker do
  use GenServer

  require Logger

  alias DoubleGisMonitor.Pipeline

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

  @spec start_pipeline() :: :ok
  def start_pipeline() do
    GenServer.cast(__MODULE__, {:start, :pipeline})
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
  def handle_cast({:start, :pipeline}, state) do
    with :ok <- Logger.info("Start pipeline"),
         {:ok, fetched} <- Pipeline.Fetch.call(),
         {:ok, processed} <- Pipeline.Process.call(fetched),
         {:ok, %{update: updated, insert: inserted}} <-
           Pipeline.Dispatch.call(processed),
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
    |> DoubleGisMonitor.WorkerTicker.set_last_result()

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

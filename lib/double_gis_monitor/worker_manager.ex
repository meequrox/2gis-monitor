defmodule DoubleGisMonitor.WorkerManager do
  @moduledoc """
  Worker that starts the event pipeline at some interval.

  Inspired by https://github.com/onboardingsystems/ticker
  """

  use GenServer

  require Logger

  alias DoubleGisMonitor.RateLimiter
  alias DoubleGisMonitor.Pipeline

  @worker_name :pipeline_worker

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

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  def init(state) do
    RateLimiter.sleep_before(__MODULE__, :init)

    send(self(), :tick)

    {:ok, state}
  end

  @impl true
  def handle_call(request, from, state) do
    Logger.warning("Received unknown call from #{inspect(from)}: #{inspect(request)}")

    {:reply, {:error, "Worker does not support calls"}, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("Received unknown cast: #{inspect(request)}")

    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    spawn_worker()
    schedule_tick()

    {:noreply, state}
  end

  def handle_info(info) do
    Logger.warning("Received unknown info: #{inspect(info)}")
  end

  defp spawn_worker(attempt \\ 0) do
    case Process.whereis(@worker_name) do
      nil ->
        Logger.info("Spawn new pipeline worker #{@worker_name}.")

        pid = Process.spawn(__MODULE__, :work, [], [:link])
        Process.register(pid, @worker_name)

      pid ->
        Logger.info(
          "[#{attempt}] The previous worker #{inspect(pid)} has not finished yet! Waiting..."
        )

        RateLimiter.sleep_before(__MODULE__, :spawn)
        spawn_worker(attempt + 1)
    end
  end

  def work() do
    Logger.info("Pipeline started.")

    with {:ok, fetched_events} <- Pipeline.Fetch.call(),
         {:ok, processed_events} <- Pipeline.Process.call(fetched_events),
         {:ok, _dispatched_events} <- Pipeline.Dispatch.call(processed_events) do
      Logger.info("Pipeline passed.")
    else
      {:error, error} -> Logger.error("Pipeline failed on #{inspect(error)}!")
    end
  end

  defp schedule_tick() do
    {:ok, interval} =
      :double_gis_monitor |> Application.fetch_env!(:fetch) |> Keyword.fetch(:interval)

    Logger.info("Schedule next pipeline start in #{interval} seconds")

    Process.send_after(self(), :tick, interval * 1000)
  end
end

defmodule DoubleGisMonitor.Worker do
  @moduledoc """
  Worker that starts the event pipeline at some interval.

  Inspired by https://github.com/onboardingsystems/ticker
  """

  use GenServer

  require Logger

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
    DoubleGisMonitor.RateLimiter.sleep_before(__MODULE__, :init)

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
    schedule_tick()
    spawn_worker()

    {:noreply, state}
  end

  def handle_info(info) do
    Logger.warning("Received unknown info: #{inspect(info)}")
  end

  defp spawn_worker(attempt \\ 0) do
    name = :pipeline_worker

    case Process.whereis(name) do
      nil ->
        Logger.info("Spawn new pipeline worker #{name}.")

        pid = Process.spawn(__MODULE__, :work, [], [:link])
        Process.register(pid, name)

      pid ->
        Logger.warning(
          "[#{attempt}] The previous worker #{inspect(pid)} has not finished yet! Waiting..."
        )

        DoubleGisMonitor.RateLimiter.sleep_before(__MODULE__, :spawn)
        spawn_worker(attempt + 1)
    end
  end

  def work() do
    Logger.info("Pipeline started.")

    {:ok, fetched_events} = DoubleGisMonitor.Pipeline.Fetch.call()
    {:ok, processed_events} = DoubleGisMonitor.Pipeline.Process.call(fetched_events)
    {:ok, _dispatched_events} = DoubleGisMonitor.Pipeline.Dispatch.call(processed_events)

    Logger.info("Pipeline passed!")
  end

  defp schedule_tick() do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)
    [interval: interval] = Keyword.take(env, [:interval])

    Logger.info("Schedule next pipeline start in #{interval} seconds")

    Process.send_after(self(), :tick, interval * 1000)
  end
end

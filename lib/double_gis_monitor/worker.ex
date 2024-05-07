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
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state) do
    Logger.info("Wait 5 seconds for other services to initialize")
    Process.sleep(5)

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
    work()

    {:noreply, state}
  end

  def handle_info(info) do
    Logger.warning("Received unknown info: #{inspect(info)}")
  end

  defp work() do
    {:ok, fetched_events} = DoubleGisMonitor.Pipeline.Fetch.call()
    {:ok, processed_events} = DoubleGisMonitor.Pipeline.Process.call(fetched_events)
    {:ok, dispatched_events} = DoubleGisMonitor.Pipeline.Dispatch.call(processed_events)

    inspect_opts = [limit: :infinity, printable_limit: :infinity, pretty: true]

    Logger.info("Work done, pipeline passed!")
    dispatched_events |> inspect(inspect_opts) |> Logger.info()
  end

  defp schedule_tick() do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)
    [interval: interval] = Keyword.take(env, [:interval])

    Process.send_after(self(), :tick, interval * 1000)
  end
end

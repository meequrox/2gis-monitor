defmodule DoubleGisMonitor.Pipeline.WorkerManager do
  @moduledoc """
  Worker Manager, which sends a command at a certain interval to start the event pipeline.

  Inspired by https://github.com/onboardingsystems/ticker
  """

  # TODO: Update @moduledoc

  use GenServer

  require Logger

  alias DoubleGisMonitor.Pipeline.Worker

  defstruct count: 0,
            last_result: :null,
            interval: 86_400,
            stages_opts: %{fetch: %{}, process: %{}, dispatch: %{}}

  @spec child_spec(map()) :: map()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_count() :: {:ok, integer()} | {:error, any()}
  def get_count() do
    GenServer.call(__MODULE__, {:get, :count})
  end

  @spec get_last_result() :: {:ok, any()} | {:error, any()}
  def get_last_result() do
    GenServer.call(__MODULE__, {:get, :last_result})
  end

  @spec get_interval() :: {:ok, integer()} | {:error, any()}
  def get_interval() do
    GenServer.call(__MODULE__, {:get, :interval})
  end

  @spec get_stages_opts() :: {:ok, map()} | {:error, any()}
  def get_stages_opts() do
    GenServer.call(__MODULE__, {:get, :stages_opts})
  end

  @spec set_last_result(any()) :: :ok
  def set_last_result(result) do
    GenServer.cast(__MODULE__, {:set, {:last_result, result}})
  end

  @impl true
  def init(%{interval: interval, stages_opts: stages_opts}) do
    state = %__MODULE__{
      interval: interval,
      stages_opts: stages_opts
    }

    send(self(), {:do, :tick})
    {:ok, state}
  end

  @impl true
  def handle_call({:get, :count}, _from, %{count: count} = state) do
    {:reply, {:ok, count}, state}
  end

  @impl true
  def handle_call({:get, :last_result}, _from, %{last_result: result} = state) do
    {:reply, {:ok, result}, state}
  end

  @impl true
  def handle_call({:get, :interval}, _from, %{interval: interval} = state) do
    {:reply, {:ok, interval}, state}
  end

  @impl true
  def handle_call({:get, :stages_opts}, _from, %{stages_opts: stages_opts} = state) do
    {:reply, {:ok, stages_opts}, state}
  end

  @impl true
  def handle_call(request, from, state) do
    Logger.warning("Received unknown call from #{inspect(from)}: #{inspect(request)}")

    {:reply, {:error, "Unknown request"}, state}
  end

  @impl true
  def handle_cast({:set, {:last_result, result}}, state) do
    # TODO: Also set last result timestamp
    {:noreply, %{state | last_result: result}}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("Received unknown cast: #{inspect(request)}")

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:do, :tick},
        %{interval: interval, count: count, stages_opts: stages_opts} = state
      ) do
    Worker.start_pipeline(stages_opts)
    schedule_tick(interval)

    {:noreply, %{state | count: count + 1}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unknown info: #{inspect(msg)}")

    {:noreply, state}
  end

  defp schedule_tick(seconds) do
    Logger.info("Schedule next pipeline start in #{seconds} seconds")

    Process.send_after(self(), {:do, :tick}, seconds * 1000)
  end
end

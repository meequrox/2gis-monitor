defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  A module that is responsible for "sleeping" the calling process for a certain time
  in order to avoid blocking by third-party web services or to eliminate conflicts within the application.

  This is a rather primitive implementation of a "just to make it work" limiter.
  The names of the modules that can access the limiter are known in advance.
  For each module, an arbitrary set of actions is supported that determine the waiting time.

  It is also important WHEN exactly to fall asleep.
  It is possible to call a limiter before executing the action itself, in which case its return value does not matter.
  A limiter can be called after executing the request, with the value it should return.
  This is done for the convenience of returning a value in the main function using pipes.
  """

  require Logger

  @default_timeout 30

  defp timeout_map() do
    %{
      :"Elixir.DoubleGisMonitor.Worker" => %{init: 5000, spawn: 10_000},
      :"Elixir.DoubleGisMonitor.Pipeline.Fetch" => %{request: 100, retry: 2000},
      :"Elixir.DoubleGisMonitor.Pipeline.Dispatch" => %{
        send: 3100,
        edit: 3100,
        retry: 3000,
        request: 100
      },
      :"Elixir.DoubleGisMonitor.Bot.Telegram" => %{send: 3100, request: 100}
    }
  end

  @spec sleep_after(any(), atom(), atom(), integer()) :: any()
  def sleep_after(return_value, module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    sleep({module, action, times}, "AFTER")
    return_value
  end

  @spec sleep_before(atom(), atom(), integer()) :: :ok
  def sleep_before(module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    sleep({module, action, times}, "BEFORE")
  end

  defp get_timeout(module, action, multiplier) do
    base_timeout = timeout_map() |> Map.get(module, %{}) |> Map.get(action, @default_timeout)

    base_timeout * multiplier
  end

  defp sleep({module, action, times}, when_) when is_binary(when_) do
    timeout = get_timeout(module, action, times)

    Logger.info("Sleeping #{timeout}ms for #{inspect(module)} #{when_} #{action}.")
    Process.sleep(timeout)
  end
end

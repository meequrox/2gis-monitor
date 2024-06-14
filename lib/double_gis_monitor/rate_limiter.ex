defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  A module that is responsible for "sleeping" the calling process for a certain time
  in order to avoid blocking by third-party web services or to eliminate conflicts within the application.

  This is a rather primitive implementation of a "just to make it work" limiter.
  The names of the modules that can access the limiter are known in advance.
  For each module, an arbitrary set of actions is supported that determine the waiting time.

  It is also important when exactly to fall asleep.
  It is possible to call a limiter before executing the action itself, in which case its return value does not matter.
  A limiter can be called after executing the request, with the value it should return.
  This is done for the convenience of returning a value in the main function using pipes.
  """

  require Logger

  @timeout_map %{
    Elixir.DoubleGisMonitor.Pipeline.Stage.Fetch => %{request: 100, retry: 2000},
    Elixir.DoubleGisMonitor.Pipeline.Stage.Dispatch => %{
      send: 3100,
      edit: 3100,
      retry: 3000,
      request: 100,
      too_many_requests: 1000
    },
    Elixir.DoubleGisMonitor.Bot.Telegram => %{send: 3100, request: 100}
  }

  @timeout_default 30

  @spec sleep_after(any(), atom(), atom(), integer()) :: any()
  def sleep_after(return_value, module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    do_sleep({module, action, times}, :after)
    return_value
  end

  @spec sleep_before(atom(), atom(), integer()) :: :ok
  def sleep_before(module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    do_sleep({module, action, times}, :before)
  end

  defp do_sleep({module, action, times}, when_) do
    timeout = get_timeout(module, action, times)

    Logger.debug("Sleeping #{timeout}ms for #{module} #{when_} #{action}.")
    Process.sleep(timeout)
  end

  defp get_timeout(module, action, multiplier) do
    @timeout_map
    |> Map.get(module, %{})
    |> Map.get(action, @timeout_default)
    |> Kernel.*(multiplier)
  end
end

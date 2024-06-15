defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  A module responsible for sleeping the calling process for a certain time in order to avoid IP blocking
  by third-party web services or to resolve conflicts within the application.

  This is a rather primitive implementation of a "just to make it work" limiter.
  The names of the modules that can access the limiter are known in advance.
  For each module, an arbitrary set of actions is supported that determine the waiting time.
  """

  require Logger

  @timeout_map %{
    Elixir.DoubleGisMonitor.Bot.Telegram => %{send: 3100, request: 100},
    Elixir.DoubleGisMonitor.Pipeline.Stage.Fetch => %{request: 100, retry: 2000},
    Elixir.DoubleGisMonitor.Pipeline.Stage.Dispatch => %{
      send: 3100,
      edit: 3100,
      retry: 3000,
      request: 100,
      too_many_requests: 1000
    }
  }

  @timeout_default 30

  @doc """
  A limiter can be called before the action itself is executed, in which case its return value has no meaning.
  """
  @spec sleep_after(term(), atom(), atom(), integer()) :: term()
  def sleep_after(return_value, module, action, times \\ 1) do
    do_sleep(module, action, times)
    return_value
  end

  @doc """
  The limiter can be called after the query has run and specified the value it should return.
  This is done for the convenience of transmitting the result using pipes.
  """
  @spec sleep_before(atom(), atom(), integer()) :: :ok
  def sleep_before(module, action, times \\ 1), do: do_sleep(module, action, times)

  defp do_sleep(module, action, times) when is_integer(times) do
    module
    |> get_timeout(action)
    |> Kernel.*(times)
    |> Process.sleep()
  end

  defp get_timeout(module, action) when is_atom(module) and is_atom(action) do
    @timeout_map
    |> Map.get(module, %{})
    |> Map.get(action, @timeout_default)
  end
end

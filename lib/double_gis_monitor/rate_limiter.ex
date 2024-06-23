defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  A module responsible for sleeping the calling process for a certain time in order to avoid IP blocking
  by third-party web services or to resolve conflicts within the application.

  This is a rather primitive implementation of a "just to make it work" limiter.
  The names of the services that can be limited are known in advance.
  For each module, an arbitrary set of actions is supported that determine the waiting time.
  """

  require Logger

  @timeout_map %{
    doublegis: %{request: 100, retry: 2000},
    telegram: %{
      request: 100,
      send: 3100,
      edit: 3100,
      retry: 3000,
      too_many_requests: 1000
    }
  }

  @timeout_default 50

  @spec sleep(atom(), atom(), integer()) :: :ok
  def sleep(service, action, times) when is_integer(times) do
    service
    |> get_timeout(action)
    |> Kernel.*(times)
    |> Process.sleep()
  end

  defp get_timeout(service, action) when is_atom(service) and is_atom(action) do
    @timeout_map
    |> Map.get(service, %{})
    |> Map.get(action, @timeout_default)
  end
end

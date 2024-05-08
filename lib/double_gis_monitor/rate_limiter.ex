defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  TODO
  """

  require Logger

  defp timeout_map() do
    %{
      :"Elixir.DoubleGisMonitor.Worker" => %{init: 5000, spawn: 10_000},
      :"Elixir.DoubleGisMonitor.Pipeline.Fetch" => %{request: 100, retry: 2000},
      :"Elixir.DoubleGisMonitor.Pipeline.Dispatch" => %{send: 3100, edit: 3100, retry: 3000},
      :"Elixir.DoubleGisMonitor.Bot.Telegram" => %{send: 3100, request: 100}
    }
  end

  defp get_timeout(module, action) when is_atom(action) do
    default_delay = 30

    timeout_map() |> Map.get(module, %{}) |> Map.get(action, default_delay)
  end

  def sleep_after(return_value, module, action, times \\ 1)
      when is_atom(action) and is_integer(times) do
    timeout = get_timeout(module, action) * times

    Logger.info("Sleeping #{timeout}ms for #{inspect(module)} AFTER #{inspect(action)}.")
    :ok = Process.sleep(timeout)

    return_value
  end

  def sleep_before(module, action, times \\ 1) when is_atom(action) and is_integer(times) do
    timeout = get_timeout(module, action) * times

    Logger.info("Sleeping #{timeout}ms for #{inspect(module)} BEFORE #{inspect(action)}.")
    :ok = Process.sleep(timeout)

    :ok
  end
end

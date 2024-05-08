defmodule DoubleGisMonitor.RateLimiter do
  @moduledoc """
  TODO
  """

  require Logger

  @default_timeout 30

  defp timeout_map() do
    %{
      :"Elixir.DoubleGisMonitor.Worker" => %{init: 5000, spawn: 10_000},
      :"Elixir.DoubleGisMonitor.Pipeline.Fetch" => %{request: 100, retry: 2000},
      :"Elixir.DoubleGisMonitor.Pipeline.Dispatch" => %{send: 3100, edit: 3100, retry: 3000},
      :"Elixir.DoubleGisMonitor.Bot.Telegram" => %{send: 3100, request: 100}
    }
  end

  defp get_timeout(module, action, multiplier) do
    base_timeout = timeout_map() |> Map.get(module, %{}) |> Map.get(action, @default_timeout)

    base_timeout * multiplier
  end

  defp sleep({module, action, times}, where) when is_binary(where) do
    timeout = get_timeout(module, action, times)

    Logger.info("Sleeping #{timeout}ms for #{inspect(module)} #{where} #{action}.")
    Process.sleep(timeout)
  end

  def sleep_after(return_value, module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    sleep({module, action, times}, "AFTER")
    return_value
  end

  def sleep_before(module, action, times \\ 1)
      when is_atom(module) and is_atom(action) and is_integer(times) do
    sleep({module, action, times}, "BEFORE")
  end
end

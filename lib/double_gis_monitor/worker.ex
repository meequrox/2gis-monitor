defmodule DoubleGisMonitor.Worker do
  require Logger

  alias DoubleGisMonitor.Pipeline

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
end

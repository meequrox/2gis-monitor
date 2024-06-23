defmodule DoubleGisMonitor.Bot.Telegram.InfoTemplate do
  def render(%{
        runs: runs_count,
        last_result: last_result,
        interval: interval,
        city: city,
        layers: layers,
        events: events_count
      }) do
    """
    <b># Service</b>
    City: #{String.capitalize(city)}
    Layers: #{inspect(layers)}

    <b># Worker</b>
    Runs count: #{runs_count}
    Interval (seconds): #{interval}
    Last result: <code>#{inspect(last_result)}</code>

    <b># Database</b>
    Events count: #{events_count}
    """
  end
end

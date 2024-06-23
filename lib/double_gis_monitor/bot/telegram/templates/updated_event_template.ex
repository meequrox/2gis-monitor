defmodule DoubleGisMonitor.Bot.Telegram.UpdatedEventTemplate do
  alias DoubleGisMonitor.Bot.Telegram.NewEventTemplate

  def render(event, timezone) do
    event
    |> NewEventTemplate.render(timezone)
    |> mark_updated(timezone)
  end

  defp mark_updated(text, timezone) do
    datetime =
      timezone
      |> DateTime.now!()
      |> Calendar.strftime("%d.%m.%y %H:%M:%S")

    """
    🔄 Updated at #{datetime} 🔄

    #{text}
    """
  end
end

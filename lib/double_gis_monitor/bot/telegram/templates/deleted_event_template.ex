defmodule DoubleGisMonitor.Bot.Telegram.DeletedEventTemplate do
  alias DoubleGisMonitor.Bot.Telegram.NewEventTemplate

  def render(event, timezone) do
    event
    |> Map.drop([:geo, :images_count, :images_list])
    |> NewEventTemplate.render(timezone)
    |> mark_deleted(timezone)
  end

  defp mark_deleted(text, timezone) do
    datetime =
      timezone
      |> DateTime.now!()
      |> Calendar.strftime("%d.%m.%y %H:%M:%S")

    """
    ❌ Deleted at #{datetime} ❌

    #{text}
    """
  end
end

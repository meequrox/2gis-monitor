defmodule DoubleGisMonitor.Bot.Telegram.NewEventTemplate do
  def render(event, timezone) do
    event
    |> create_meta(timezone)
    |> append_username(event)
    |> append_comment(event)
    |> append_feedback(event)
    |> append_images(event)
    |> append_link(event)
    |> append_geo(event)
  end

  defp create_meta(%{timestamp: timestamp, type: type}, timezone) do
    emoji = type_to_emoji(type)
    datetime = timestamp_to_local_dt(timestamp, timezone)

    """
    #{emoji} #{datetime}
    """
  end

  defp append_username(msg, %{username: username}) when is_binary(username) do
    msg <>
      ("""
       #{username}
       """
       |> Telegex.Tools.safe_html())
  end

  defp append_username(msg, _event), do: msg

  defp append_comment(msg, %{comment: comment}) when is_binary(comment) do
    msg <>
      ("""

       #{comment}
       """
       |> Telegex.Tools.safe_html())
  end

  defp append_comment(msg, _event), do: msg

  defp append_feedback(msg, %{likes: likes, dislikes: dislikes})
       when is_integer(likes) and is_integer(dislikes) do
    msg <>
      "\n" <>
      "#{likes} 👍 | 👎 #{dislikes}"
  end

  defp append_images(msg, %{images_count: count}) when is_integer(count) and count > 0 do
    msg <>
      """

      Images: #{count}
      """
  end

  defp append_images(msg, _event), do: msg

  defp append_link(msg, %{city: city, geo: [lat, lon]})
       when is_float(lat) and is_float(lon) and is_binary(city) do
    params = %{m: "#{lon},#{lat}", traffic: ""}
    url = HTTPoison.Base.build_request_url("https://2gis.ru/#{city}", params)

    msg <>
      "\n" <>
      "<a href=\"#{url}\">" <>
      "Open in 2GIS" <>
      "</a>"
  end

  defp append_link(msg, _event), do: msg

  defp append_geo(msg, %{geo: [lat, lon]})
       when is_float(lat) and is_float(lon) do
    lat_rounded = Float.round(lat, 6)
    lon_rounded = Float.round(lon, 6)

    msg <>
      " | <code>" <>
      "#{lat_rounded},#{lon_rounded}" <>
      "</code>"
  end

  defp append_geo(msg, _event), do: msg

  defp type_to_emoji(type) do
    case type do
      "camera" -> "📸"
      "crash" -> "💥"
      "roadwork" -> "🚧"
      "restriction" -> "⛔"
      "comment" -> "💬"
      "other" -> "⚠️"
      unknown -> unknown
    end
  end

  defp timestamp_to_local_dt(timestamp, timezone) do
    timestamp
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%d.%m.%y %H:%M:%S")
  end
end

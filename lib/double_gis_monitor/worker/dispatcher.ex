defmodule DoubleGisMonitor.Event.Dispatcher do
  alias DoubleGisMonitor.Worker.Poller
  alias DoubleGisMonitor.Db.Repo

  require Logger

  def dispatch(events) when is_map(events) do
    dispatcher = Process.spawn(__MODULE__, :dispatch, [:spawned, events], [:link])

    Logger.info("Dispatcher spawned: #{inspect(dispatcher)}")
  end

  def dispatch(:spawned, %{:update => updated_events, :insert => inserted_events})
      when is_list(updated_events) and is_list(inserted_events) do
    # dispatch_updates(updated_events)
    dispatch_inserts(inserted_events)
  end

  def dispatch_updates(events) do
    msg_fn =
      fn e ->
        _text = prepare_text(e)

        chat_fn =
          fn %{:id => _id} ->
            # TODO: update message

            Process.sleep(3000)
          end

        Enum.each(Repo.get_chats(), chat_fn)
      end

    Enum.each(events, msg_fn)
  end

  def dispatch_inserts(events) do
    text_fn =
      fn e ->
        text = prepare_text(e)

        chat_fn =
          fn %{:id => id} ->
            Process.sleep(3000)

            # TODO: DISABLE PREVIEW!
            case ExGram.send_message(id, text, parse_mode: "HTML", disable_web_page_preview: true) do
              {:ok, _message} ->
                # Repo.add_message()
                :ok

              {:error, error} ->
                Logger.error("Failed to send new message to chat #{id}: #{inspect(error)}")
            end
          end

        Enum.each(Repo.get_chats(), chat_fn)
      end

    Enum.each(events, text_fn)
  end

  defp prepare_text(event) do
    create_meta(event)
    |> append_username(event)
    |> append_comment(event)
    |> append_feedback(event)
    |> normalize_text()
    |> append_link(event)
    |> append_attachments(event)
  end

  defp create_meta(%{:timestamp => ts, :type => type}) when is_integer(ts) and is_binary(type) do
    "#{type_to_emoji(type)} #{timestamp_to_local_dt(ts)}"
  end

  defp create_meta(_e), do: ""

  defp append_username(msg, %{:username => username}) when is_binary(username) do
    msg <> "\n#{username}\n"
  end

  defp append_username(msg, _e), do: msg

  defp append_comment(msg, %{:comment => comment}) when is_binary(comment) do
    msg <> "\n#{comment}\n"
  end

  defp append_comment(msg, _e), do: msg

  defp append_feedback(msg, %{:likes => likes, :dislikes => dislikes})
       when is_integer(likes) and is_integer(dislikes) do
    msg <> "\n#{likes} 👍 | 👎 #{dislikes}"
  end

  defp append_feedback(msg, _e), do: msg

  defp append_link(msg, %{:coordinates => %{:lat => lat, :lon => lon}})
       when is_float(lat) and is_float(lon) do
    poller_state = Agent.get(Poller, fn m -> m end)

    params = %{m: "#{lon},#{lat}"}

    url =
      HTTPoison.Base.build_request_url("https://2gis.ru/#{poller_state.city}", params) <>
        "/18?traffic="

    msg <> "\n<a href=\"#{url}\">Open in 2GIS</a>\n"
  end

  defp append_link(msg, _e), do: msg

  defp append_attachments(msg, %{:attachments_count => count, :attachments_list => list})
       when is_integer(count) and is_list(list) and count > 0 do
    # TODO: really append attachments
    msg <> "#{count} attachments"
  end

  defp append_attachments(msg, _e), do: msg

  defp normalize_text(text) do
    text
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("&", "&amp;")
  end

  defp type_to_emoji(t) do
    case t do
      "camera" -> "📸"
      "crash" -> "💥"
      "roadwork" -> "🦺"
      "restriction" -> "⛔"
      "comment" -> "💬"
      "other" -> "❔"
      unknown -> unknown
    end
  end

  defp timestamp_to_local_dt(ts) do
    tz = Application.fetch_env!(:double_gis_monitor, :dispatcher) |> Keyword.get(:timezone)

    ts
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(tz, TimeZoneInfo.TimeZoneDatabase)
    |> Calendar.strftime("%d.%m.%y %H:%M:%S")
  end
end

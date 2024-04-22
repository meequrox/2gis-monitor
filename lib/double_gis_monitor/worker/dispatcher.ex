defmodule DoubleGisMonitor.Worker.Dispatcher do
  require Logger

  alias DoubleGisMonitor.Worker.Poller
  alias DoubleGisMonitor.Db
  alias ExGram.Model

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
      fn _e ->
        # text = prepare_text(e)
        # media = build_media(e, text)

        chat_fn =
          fn %{:id => _id} ->
            # TODO: update message
            # ExGram.edit_message_text()
            # ExGram.edit_message_caption()

            Process.sleep(3000)
          end

        Enum.each(Db.Utils.Chat.all(), chat_fn)
      end

    Enum.each(events, msg_fn)
  end

  def dispatch_inserts(events) do
    active_chats = Db.Utils.Chat.all()

    event_fn =
      fn event ->
        text = prepare_text(event)
        media = build_media(event, text)

        chat_fn = fn %{:id => chat_id} -> dispatch_event(chat_id, event, {text, media}) end
        Enum.each(active_chats, chat_fn)
      end

    Enum.each(events, event_fn)
  end

  defp dispatch_event(chat_id, event, {text, media}) do
    case send_event_message(chat_id, event, {text, media}) do
      {:ok, messages} when is_list(messages) ->
        message_ids = Enum.map(messages, fn m -> m.message_id end)

        case Db.Utils.Message.insert_or_update(event.uuid, chat_id, message_ids) do
          {:ok, res} ->
            Logger.info("Link created: #{inspect(res)}")

          {:error, c} ->
            # TODO: Log error
            c
        end

      {:error, error} ->
        Logger.error("Failed to send new message to chat #{chat_id}: #{inspect(error)}")
    end
  end

  defp send_event_message(chat_id, event, {text, media}) do
    link_preview_opts = %Model.LinkPreviewOptions{is_disabled: true}
    send_opts = [parse_mode: "HTML", link_preview_options: link_preview_opts]

    Process.sleep(500)

    case event.attachments_count do
      0 ->
        case ExGram.send_message(chat_id, text, send_opts) do
          {:ok, msg} -> {:ok, [msg]}
          {:error, err} -> {:error, err}
        end

      _ ->
        ExGram.send_media_group(chat_id, media)
    end
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

    msg <> "\n\n<a href=\"#{url}\">Open in 2GIS</a>\n"
  end

  defp append_link(msg, _e), do: msg

  defp append_attachments(msg, %{:attachments_count => count})
       when is_integer(count) and count > 0 do
    msg <> "\nAttachments: #{count}"
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

  defp build_media(%{:attachments_count => count, :attachments_list => list}, text) do
    reduce_fn =
      fn url, acc ->
        case acc do
          0 ->
            {%Model.InputMediaPhoto{type: "photo", media: url, caption: text, parse_mode: "HTML"},
             acc + 1}

          _ ->
            {%Model.InputMediaPhoto{type: "photo", media: url}, acc + 1}
        end
      end

    case count do
      0 ->
        []

      _ ->
        {result, _} = Enum.map_reduce(list, 0, reduce_fn)

        result
    end
  end
end

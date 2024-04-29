defmodule DoubleGisMonitor.Pipeline.Dispatch do
  require DoubleGisMonitor.Bot.Telegram
  require Logger

  def call(%{:update => updated_events, :insert => inserted_events})
      when is_list(updated_events) and is_list(inserted_events) do
    with {:ok, updated_messages} <- dispatch(:update, updated_events),
         {:ok, inserted_messages} <- dispatch(:insert, inserted_events) do
      Logger.info(
        "#{Enum.count(updated_messages)} updates and #{Enum.count(inserted_messages)} new messages dispatched."
      )

      {:ok, %{:update => updated_messages, :insert => inserted_messages}}
    else
      {:error, {:insert_messages, changeset}} ->
        Logger.error("Failed to insert new messages: #{inspect(changeset)}")
        {:error, :insert_messages}
    end
  end

  def dispatch(:insert, events) when is_list(events) do
    with {:ok, sent_messages} <- send_messages(events),
         {:ok, inserted_messages} <- insert_messages(sent_messages) do
      {:ok, inserted_messages}
    else
      error -> error
    end
  end

  def dispatch(:update, events) when is_list(events) do
    with {:ok, linked_events} <- link_updates_with_messages(events),
         {:ok, messages} <- update_messages(linked_events) do
      {:ok, messages}
    end
  end

  def insert_messages(messages) when is_list(messages) do
    transaction_fun =
      fn ->
        for message <- messages do
          case DoubleGisMonitor.Db.Repo.insert(message, returning: false) do
            {:ok, struct} -> struct
            {:error, changeset} -> DoubleGisMonitor.Db.Repo.rollback({:insert, changeset})
          end
        end
      end

    case DoubleGisMonitor.Db.Repo.transaction(transaction_fun) do
      {:ok, inserted_messages} ->
        {:ok, inserted_messages}

      {:error, {:insert, changeset}} ->
        Logger.error("Failed to insert new message: #{inspect(changeset)}. Rolled back.")
        {:error, {:insert_messages, changeset}}
    end
  end

  defp send_messages(events) when is_list(events) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [channel_id: channel_id] = Keyword.take(env, [:channel_id])

    map_fun =
      fn event ->
        case send_event_message(channel_id, event) do
          {:ok, db_message} ->
            db_message

          {:error, error} ->
            Logger.error("Failed to send new event message: #{inspect({event, error})}")
            %DoubleGisMonitor.Db.Message{uuid: nil}
        end
      end

    filter_fun = fn %DoubleGisMonitor.Db.Message{:uuid => uuid} -> not is_nil(uuid) end

    messages = events |> Enum.map(map_fun) |> Enum.filter(filter_fun)

    {:ok, messages}
  end

  defp send_event_message(
         channel_id,
         %DoubleGisMonitor.Db.Event{:uuid => uuid, :attachments => %{:count => attachments_count}} =
           event
       )
       when is_integer(channel_id) and is_binary(uuid) and is_integer(attachments_count) do
    link_preview_opts = %Telegex.Type.LinkPreviewOptions{is_disabled: true}

    text = prepare_text(event)
    media = build_media(event, text)

    case attachments_count do
      0 ->
        opts = [parse_mode: "HTML", link_preview_options: link_preview_opts]

        Process.sleep(DoubleGisMonitor.Bot.Telegram.send_delay())

        case Telegex.send_message(channel_id, text, opts) do
          {:ok, %Telegex.Type.Message{:message_id => message_id}} ->
            db_message = %DoubleGisMonitor.Db.Message{
              uuid: uuid,
              type: "text",
              count: 1,
              list: [message_id]
            }

            {:ok, db_message}

          {:error, error} ->
            {:error, error}
        end

      count ->
        Process.sleep(DoubleGisMonitor.Bot.Telegram.send_delay())

        case Telegex.send_media_group(channel_id, media) do
          {:ok, messages} ->
            list =
              for %Telegex.Type.Message{:message_id => message_id} <- messages, do: message_id

            db_message = %DoubleGisMonitor.Db.Message{
              uuid: uuid,
              type: "caption",
              count: count,
              list: list
            }

            Process.sleep(DoubleGisMonitor.Bot.Telegram.send_delay() * (count - 1))
            {:ok, db_message}

          {:error, error} ->
            Process.sleep(DoubleGisMonitor.Bot.Telegram.send_delay())
            {:error, error}
        end
    end
  end

  defp build_media(
         %DoubleGisMonitor.Db.Event{:attachments => %{:count => count, :list => list}},
         text
       )
       when is_integer(count) and is_list(list) and is_binary(text) do
    reduce_fun =
      fn url, acc ->
        media =
          case acc do
            0 ->
              %Telegex.Type.InputMediaPhoto{
                type: "photo",
                media: url,
                caption: text,
                parse_mode: "HTML"
              }

            _greater ->
              %Telegex.Type.InputMediaPhoto{type: "photo", media: url}
          end

        {media, acc + 1}
      end

    case count do
      0 ->
        []

      _greater ->
        {media_list, _acc} = Enum.map_reduce(list, 0, reduce_fun)

        media_list
    end
  end

  def update_messages(events) when is_list(events) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz, channel_id: channel_id] = Keyword.take(env, [:timezone, :channel_id])

    datetime =
      tz |> DateTime.now!(TimeZoneInfo.TimeZoneDatabase) |> Calendar.strftime("%d.%m.%y %H:%M:%S")

    map_fun =
      fn event ->
        text = "Updated at " <> datetime <> "\n\n" <> prepare_text(event)

        case update_message(event, channel_id, text) do
          {:error, error} ->
            Logger.error("Failed to update event message: #{inspect({event, error})}")
            nil

          {:ok, msg} ->
            msg
        end
      end

    messages = events |> Enum.map(map_fun) |> Enum.filter(fn msg -> not is_nil(msg) end)

    {:ok, messages}
  end

  defp update_message(%{:linked_messages => linked_messages}, channel_id, text)
       when is_map(linked_messages) and is_integer(channel_id) and is_binary(text) do
    Process.sleep(DoubleGisMonitor.Bot.Telegram.send_delay())

    case linked_messages do
      %DoubleGisMonitor.Db.Message{:type => "text", :count => 1, :list => [message_id]} = msg ->
        case Telegex.edit_message_text(text,
               chat_id: channel_id,
               message_id: message_id,
               parse_mode: "HTML"
             ) do
          {:ok, _message} -> {:ok, msg}
          {:error, error} -> {:error, error}
        end

      %DoubleGisMonitor.Db.Message{:type => "caption", :list => [message_id | _rest]} = msg ->
        case Telegex.edit_message_caption(
               chat_id: channel_id,
               message_id: message_id,
               caption: text,
               parse_mode: "HTML"
             ) do
          {:ok, _message} -> {:ok, msg}
          {:error, error} -> {:error, error}
        end
    end
  end

  defp prepare_text(event) when is_map(event) do
    create_meta(event)
    |> append_username(event)
    |> append_comment(event)
    |> append_feedback(event)
    |> Telegex.Tools.safe_html()
    |> append_attachments(event)
    |> append_link(event)
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

  defp append_feedback(msg, %{:feedback => %{:likes => likes, :dislikes => dislikes}})
       when is_integer(likes) and is_integer(dislikes) do
    msg <> "\n#{likes} 👍 | 👎 #{dislikes}"
  end

  defp append_feedback(msg, _e), do: msg

  defp append_link(msg, %{:coordinates => %{:lat => lat, :lon => lon}})
       when is_float(lat) and is_float(lon) do
    env = Application.get_env(:double_gis_monitor, :fetch, [])
    [city: city] = Keyword.take(env, [:city])

    params = %{m: "#{lon},#{lat}"}

    url = HTTPoison.Base.build_request_url("https://2gis.ru/#{city}", params) <> "/18?traffic="

    msg <> "\n<a href=\"#{url}\">Open in 2GIS</a>"
  end

  defp append_link(msg, _e), do: msg

  defp append_attachments(msg, %{:attachments => %{:count => count}})
       when is_integer(count) and count > 0 do
    msg <> "\n\nAttachments: #{count}\n"
  end

  defp append_attachments(msg, _e), do: msg

  defp type_to_emoji(type) when is_binary(type) do
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

  defp timestamp_to_local_dt(ts) when is_integer(ts) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz] = Keyword.take(env, [:timezone])

    ts
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(tz, TimeZoneInfo.TimeZoneDatabase)
    |> Calendar.strftime("%d.%m.%y %H:%M:%S")
  end

  defp link_updates_with_messages(events) when is_list(events) do
    map_fun =
      fn %DoubleGisMonitor.Db.Event{:uuid => uuid} = event ->
        messages =
          case DoubleGisMonitor.Db.Repo.get(DoubleGisMonitor.Db.Message, uuid) do
            nil -> %DoubleGisMonitor.Db.Message{uuid: nil}
            any -> any
          end

        Map.put(event, :linked_messages, messages)
      end

    filter_fun = fn %{:linked_messages => %DoubleGisMonitor.Db.Message{:uuid => t}} ->
      not is_nil(t)
    end

    linked_events = events |> Enum.map(map_fun) |> Enum.filter(filter_fun)

    {:ok, linked_events}
  end
end
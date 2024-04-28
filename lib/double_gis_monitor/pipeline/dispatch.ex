defmodule DoubleGisMonitor.Pipeline.Dispatch do
  require Logger

  def call(%{:update => updated_events, :insert => inserted_events})
      when is_list(updated_events) and is_list(inserted_events) do
    # TODO: handle errors
    with {:ok, updated_messages} <- dispatch(:update, updated_events),
         {:ok, new_messages} <- dispatch(:insert, inserted_events) do
      {:ok, %{:update => updated_messages, :new => new_messages}}
    end
  end

  def dispatch(:insert, events) when is_list(events) do
    # TODO: handle errors
    with {:ok, sent_messages} <- send_messages(events),
         {:ok, sent_messages} <- insert_new_messages(sent_messages) do
      {:ok, sent_messages}
    end
  end

  def dispatch(:update, events) when is_list(events) do
    # TODO: handle errors
    with {:ok, linked_events} <- link_updates_with_messages(events),
         {:ok, messages} <- update_messages(linked_events) do
      {:ok, messages}
    end
  end

  def insert_new_messages(messages) do
    # TODO
    {:ok, messages}
  end

  defp send_messages(events) when is_list(events) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [channel_id: channel_id] = Keyword.take(env, [:channel_id])

    # TODO: check returns
    result =
      for event <- events do
        case send_event_message(channel_id, event) do
          {:ok, db_message} ->
            db_message

          {:error, _err} ->
            %DoubleGisMonitor.Db.Message{uuid: :invalid}
        end
      end
      |> Enum.filter(fn %DoubleGisMonitor.Db.Message{:uuid => uuid} -> uuid != :invalid end)

    {:ok, result}
  end

  defp send_event_message(channel_id, event) when is_map(event) do
    link_preview_opts = %Telegex.Type.LinkPreviewOptions{is_disabled: true}

    text = prepare_text(event)
    media = build_media(event, text)

    # TODO: check returns
    case event.attachments.count do
      0 ->
        case Telegex.send_message(channel_id, text,
               parse_mode: "HTML",
               link_preview_options: link_preview_opts
             ) do
          {:ok, message} ->
            {:ok,
             %DoubleGisMonitor.Db.Message{
               uuid: event.uuid,
               type: "text",
               count: 1,
               list: [message.message_id]
             }}

          {:error, err} ->
            {:error, err}
        end

      count ->
        case Telegex.send_media_group(channel_id, media) do
          {:ok, messages} ->
            list =
              for %Telegex.Type.Message{:message_id => message_id} <- messages, do: message_id

            {:ok,
             %DoubleGisMonitor.Db.Message{
               uuid: event.uuid,
               type: "caption",
               count: count,
               list: list
             }}

          {:error, err} ->
            {:error, err}
        end
    end
  end

  defp build_media(%{:attachments => %{:count => count, :list => list}}, text) do
    # TODO: check returns
    reduce_fn =
      fn url, acc ->
        case acc do
          0 ->
            {%Telegex.Type.InputMediaPhoto{
               type: "photo",
               media: url,
               caption: text,
               parse_mode: "HTML"
             }, acc + 1}

          _ ->
            {%Telegex.Type.InputMediaPhoto{type: "photo", media: url}, acc + 1}
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

  def update_messages(events) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz, channel_id: channel_id] = Keyword.take(env, [:timezone, :channel_id])

    # TODO: check returns
    # TODO: fix local return
    # TODO: split?
    map_fun =
      fn event ->
        datetime =
          tz
          |> DateTime.now(TimeZoneInfo.TimeZoneDatabase)
          |> Calendar.strftime("%d.%m.%y %H:%M:%S")

        text = "Updated at " <> datetime <> "\n\n" <> prepare_text(event)

        result =
          case event.linked_messages do
            %DoubleGisMonitor.Db.Message{:type => "none"} = msg ->
              {:ok, msg}

            %DoubleGisMonitor.Db.Message{:type => "text", :count => 1, :list => [message_id]} =
                msg ->
              Process.sleep(100)

              case Telegex.edit_message_text(text,
                     chat_id: channel_id,
                     message_id: message_id,
                     parse_mode: "HTML"
                   ) do
                {:ok, _message} -> {:ok, msg}
                {:error, error} -> {:error, error}
              end

            %DoubleGisMonitor.Db.Message{:type => "caption", :list => [message_id | _rest]} = msg ->
              Process.sleep(100)

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

        case result do
          {:error, error} ->
            Logger.error("Failed to edit message: #{inspect(error)}")
            {:error, error}

          {:ok, message} ->
            message
        end
      end

    messages = Enum.map(events, map_fun)

    {:ok, messages}
  end

  defp prepare_text(event) do
    create_meta(event)
    |> append_username(event)
    |> append_comment(event)
    |> append_feedback(event)
    |> Telegex.Tools.safe_html()
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

  defp append_feedback(msg, %{:feedback => %{:likes => likes, :dislikes => dislikes}})
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

  defp append_attachments(msg, %{:attachments => %{:count => count}})
       when is_integer(count) and count > 0 do
    msg <> "\nAttachments: #{count}"
  end

  defp append_attachments(msg, _e), do: msg

  defp type_to_emoji(t) do
    case t do
      "camera" -> "📸"
      "crash" -> "💥"
      "roadwork" -> "⚒️"
      "restriction" -> "⛔"
      "comment" -> "💬"
      "other" -> "❔"
      unknown -> unknown
    end
  end

  defp timestamp_to_local_dt(ts) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz] = Keyword.take(env, [:timezone])

    ts
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(tz, TimeZoneInfo.TimeZoneDatabase)
    |> Calendar.strftime("%d.%m.%y %H:%M:%S")
  end

  defp link_updates_with_messages(events) when is_list(events) do
    linked_events =
      for %DoubleGisMonitor.Db.Event{:uuid => uuid} = event <- events do
        messages =
          case DoubleGisMonitor.Db.Repo.get(DoubleGisMonitor.Db.Message, uuid) do
            nil -> %DoubleGisMonitor.Db.Message{uuid: uuid, type: "none", count: 0, list: []}
            any -> any
          end

        Map.put(event, :linked_messages, messages)
      end

    {:ok, linked_events}
  end
end

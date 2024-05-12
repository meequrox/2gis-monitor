defmodule DoubleGisMonitor.Pipeline.Dispatch do
  @moduledoc """
  A pipeline module that receives a map of updated and inserted events and sends these changes to the Telegram bot.

  For updated events, simply edit the previous sent message.
  Due to Telegram's architecture, it is not possible to add new attachments for updated events.
  As a workaround, an "Updated at ..." title will be added to the top of the updated event message.

  Due to Telegram Bot's API limitations on sending messages in a single channel, it will only send 1 message per second.
  If the event has attachments, the dispatcher will send a message with them and then sleep for as many seconds as the event has attachments.
  """

  require DoubleGisMonitor.Bot.Telegram
  require Logger

  alias DoubleGisMonitor.RateLimiter
  alias DoubleGisMonitor.Db, as: Database

  @spec call(%{update: list(map()), insert: list(map())}) ::
          {:ok, %{update: list(map()), insert: list(map())}} | {:error, atom()}
  def call(%{:update => updated_events, :insert => inserted_events})
      when is_list(updated_events) and is_list(inserted_events) do
    with {:ok, updated_messages} <- dispatch(:update, updated_events),
         {:ok, inserted_messages} <- dispatch(:insert, inserted_events) do
      "#{Enum.count(updated_messages)} updates and #{Enum.count(inserted_messages)} new messages dispatched."
      |> Logger.info()

      {:ok, %{:update => updated_messages, :insert => inserted_messages}}
    else
      {:error, {:insert_messages, changeset}} ->
        Logger.error("Failed to insert new messages: #{inspect(changeset)}")
        {:error, :insert_messages}
    end
  end

  defp dispatch(:insert, events) when is_list(events) do
    with {:ok, sent_messages} <- send_messages(events),
         {:ok, inserted_messages} <- insert_messages(sent_messages) do
      {:ok, inserted_messages}
    else
      error -> error
    end
  end

  defp dispatch(:update, events) when is_list(events) do
    with {:ok, linked_events} <- link_updates_with_messages(events),
         {:ok, messages} <- update_messages(linked_events) do
      {:ok, messages}
    else
      error -> error
    end
  end

  defp insert_messages(messages) when is_list(messages) do
    transaction_fun =
      fn ->
        for message <- messages do
          case Database.Repo.insert(message, returning: false) do
            {:ok, struct} -> struct
            {:error, changeset} -> Database.Repo.rollback({:insert, changeset})
          end
        end
      end

    case Database.Repo.transaction(transaction_fun) do
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
            %Database.Message{uuid: nil}
        end
      end

    filter_fun = fn %Database.Message{:uuid => uuid} -> not is_nil(uuid) end

    messages = events |> Enum.map(map_fun) |> Enum.filter(filter_fun)

    {:ok, messages}
  end

  defp send_event_message(
         channel_id,
         %Database.Event{:attachments => %{:count => attachments_count}} = event
       )
       when is_integer(channel_id) and is_integer(attachments_count) do
    case attachments_count do
      0 ->
        send_event_single_message(channel_id, event)

      _greater ->
        send_event_group_message(channel_id, event)
    end
  end

  defp send_event_single_message(
         channel_id,
         %Database.Event{:uuid => uuid, :attachments => %{:count => attachments_count}} =
           event,
         attempt \\ 0
       )
       when is_integer(channel_id) and is_binary(uuid) and is_integer(attachments_count) and
              is_integer(attempt) do
    link_preview_opts = %Telegex.Type.LinkPreviewOptions{is_disabled: true}
    opts = [parse_mode: "HTML", link_preview_options: link_preview_opts]

    text = prepare_text(event)

    case Telegex.send_message(channel_id, text, opts) do
      {:ok, %Telegex.Type.Message{:message_id => message_id}} ->
        db_message = %Database.Message{
          uuid: uuid,
          type: "text",
          count: 1,
          list: [message_id]
        }

        RateLimiter.sleep_after({:ok, db_message}, __MODULE__, :send)

      {:error, error} ->
        case attempt do
          3 ->
            {:error, error}

          below ->
            Logger.warning("Failed to send single message for event #{uuid}. Retrying...")

            RateLimiter.sleep_before(__MODULE__, :retry)
            send_event_single_message(channel_id, event, below + 1)
        end
    end
  end

  defp send_event_group_message(
         channel_id,
         %Database.Event{:uuid => uuid, :attachments => %{:count => attachments_count}} =
           event,
         attempt \\ 0
       )
       when is_integer(channel_id) and is_binary(uuid) and is_integer(attachments_count) and
              is_integer(attempt) do
    text = prepare_text(event)
    media = build_media(event, text)

    case Telegex.send_media_group(channel_id, media) do
      {:ok, messages} ->
        list =
          for %Telegex.Type.Message{:message_id => message_id} <- messages, do: message_id

        db_message = %Database.Message{
          uuid: uuid,
          type: "caption",
          count: attachments_count,
          list: list
        }

        RateLimiter.sleep_after(
          {:ok, db_message},
          __MODULE__,
          :send,
          attachments_count
        )

      {:error, error} ->
        case attempt do
          3 ->
            {:error, error}

          below ->
            Logger.warning("Failed to send media group for event #{uuid}. Retrying...")

            RateLimiter.sleep_before(__MODULE__, :retry)
            send_event_group_message(channel_id, event, below + 1)
        end
    end
  end

  defp build_media(
         %Database.Event{:attachments => %{:count => count, :list => list}},
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

  defp update_messages(events) when is_list(events) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz, channel_id: channel_id] = Keyword.take(env, [:timezone, :channel_id])

    datetime =
      tz
      |> DateTime.now!(TimeZoneInfo.TimeZoneDatabase)
      |> Calendar.strftime("%d.%m.%y %H:%M:%S")

    map_fun =
      fn event ->
        text = "🔄 Updated at " <> datetime <> " 🔄\n\n" <> prepare_text(event)

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

  defp update_message(
         %{
           :linked_messages => %Database.Message{
             :type => type,
             :count => count,
             :list => [first_message_id | _rest]
           }
         } = event,
         channel_id,
         text,
         attempt \\ 0
       ) do
    case update_message_based_on_type({type, count}, channel_id, text, first_message_id) do
      {:ok, message} ->
        RateLimiter.sleep_after({:ok, message}, __MODULE__, :edit)

      {:error, %Telegex.Error{error_code: 400} = error} ->
        RateLimiter.sleep_after({:error, error}, __MODULE__, :request)

      {:error, error} ->
        handle_update_message_error(error, event, channel_id, text, attempt)
    end
  end

  defp handle_update_message_error(
         %Telegex.Error{:error_code => code, :description => desc} = error,
         %{:uuid => uuid, :linked_messages => %Database.Message{:type => type}} =
           event,
         channel_id,
         text,
         attempt
       ) do
    case code do
      429 ->
        "Too Many Requests: retry after " <> timeout = desc
        seconds = timeout |> String.to_integer()

        if seconds > 300 do
          ^seconds = 300
        end

        "Caught #{timeout} seconds rate limit! Will sleep for #{seconds} seconds..."
        |> Logger.error()
        |> RateLimiter.sleep_after(__MODULE__, :too_many_requests, seconds)

      _ ->
        :ok
    end

    case attempt do
      3 ->
        {:error, error}

      below ->
        Logger.warning("Failed to update #{type} message for event #{uuid}. Retrying...")

        RateLimiter.sleep_before(__MODULE__, :retry)
        update_message(event, channel_id, text, below + 1)
    end
  end

  defp update_message_based_on_type({type, count}, channel_id, text, first_message_id)
       when is_binary(type) and is_integer(count) and is_integer(channel_id) and is_binary(text) and
              is_integer(first_message_id) do
    case {type, count} do
      {"text", 1} ->
        Telegex.edit_message_text(text,
          chat_id: channel_id,
          message_id: first_message_id,
          parse_mode: "HTML"
        )

      {"caption", _} ->
        Telegex.edit_message_caption(
          chat_id: channel_id,
          message_id: first_message_id,
          caption: text,
          parse_mode: "HTML"
        )
    end
  end

  defp prepare_text(event) when is_map(event) do
    create_meta(event)
    |> append_username(event)
    |> append_comment(event)
    |> append_feedback(event)
    |> append_attachments(event)
    |> Telegex.Tools.safe_html()
    |> append_link(event)
    |> append_geo(event)
  end

  defp create_meta(%{:timestamp => ts, :type => type}) when is_integer(ts) and is_binary(type) do
    "#{type_to_emoji(type)} #{timestamp_to_local_dt(ts)}\n"
  end

  defp create_meta(_e), do: ""

  defp append_username(msg, %{:username => username}) when is_binary(username) do
    msg <> "#{username}\n"
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

  defp append_attachments(msg, %{:attachments => %{:count => count}})
       when is_integer(count) and count > 0 do
    msg <> "\n\nAttachments: #{count}\n"
  end

  defp append_attachments(msg, _e), do: msg

  defp append_link(msg, %{:coordinates => %{:lat => lat, :lon => lon}})
       when is_float(lat) and is_float(lon) do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)
    [city: city] = Keyword.take(env, [:city])

    params = %{m: "#{lon},#{lat}"}

    url = HTTPoison.Base.build_request_url("https://2gis.ru/#{city}", params) <> "/18?traffic="

    msg <> "\n<a href=\"#{url}\">Open in 2GIS</a>"
  end

  defp append_link(msg, _e), do: msg

  defp append_geo(msg, %{:coordinates => %{:lat => lat, :lon => lon}})
       when is_float(lat) and is_float(lon) do
    msg <> " <span class=\"tg-spoiler\">#{Float.round(lat, 6)}, #{Float.round(lon, 6)}</span>"
  end

  defp append_geo(msg, _e), do: msg

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
      fn %Database.Event{:uuid => uuid} = event ->
        messages =
          case Database.Repo.get(Database.Message, uuid) do
            nil -> %Database.Message{uuid: nil}
            any -> any
          end

        Map.put(event, :linked_messages, messages)
      end

    filter_fun = fn %{:linked_messages => %Database.Message{:uuid => t}} ->
      not is_nil(t)
    end

    linked_events = events |> Enum.map(map_fun) |> Enum.filter(filter_fun)

    {:ok, linked_events}
  end
end

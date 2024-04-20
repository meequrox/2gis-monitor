defmodule DoubleGisMonitor.Bot.Telegram do
  @bot :double_gis_monitor

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  require Logger

  alias DoubleGisMonitor.Bot.Telegram.Middleware
  alias ExGram.Model

  command("start")
  command("help", description: "Print the bot's help")
  command("info", description: "Print current service status")

  middleware(Middleware.IgnorePrivateMessages)

  def init(_opts) do
    sticker = "CAACAgIAAxkBAAEq9l9mJAEHn6OZOrDIubls8uoa4dPkXgAChRYAAq4CEEo2ULUhfmVsyTQE"

    # TODO: get chats from database
    chats = []

    Enum.each(chats, fn id -> ExGram.send_sticker!(id, sticker) end)
  end

  def bot(), do: @bot

  def handle(msg, %ExGram.Cnt{:extra => %{:rejected => true} = cnt}) do
    Logger.warning("Message was rejected by middleware: #{inspect(msg)}")

    cnt
  end

  def handle(
        {:command, "start@" <> _b, %Model.Message{:chat => %Model.Chat{:id => chat_id}}},
        cnt
      ) do
    reply =
      "Hi! This bot will perform the distribution of event updates on the 2GIS map in this chat."

    # TODO: add chat to database (or remove if 403)
    ExGram.send_message!(chat_id, reply)

    cnt
  end

  def handle(
        {:command, "info@" <> _b, %Model.Message{:chat => %Model.Chat{:id => chat_id}}},
        cnt
      ) do
    %{city: city, layers: layers, interval: interval} =
      Agent.get(DoubleGisMonitor.Event.Poller, fn map -> map end)

    %{last_cleanup: last_cleanup} = Agent.get(DoubleGisMonitor.Event.Processor, fn map -> map end)

    reply =
      "City: #{String.capitalize(city)}" <>
        "\nLayers: `#{layers}`" <>
        "\nInterval: #{trunc(interval / 1000)} seconds" <>
        "\nLast database cleanup: #{DateTime.diff(DateTime.utc_now(), last_cleanup, :hour)} hours ago"

    ExGram.send_message!(chat_id, reply, parse_mode: "MarkdownV2")

    cnt
  end

  def handle(
        {:command, "help@" <> _b, %Model.Message{:chat => %Model.Chat{:id => chat_id}}},
        %ExGram.Cnt{:bot_info => %Model.User{:username => bot_username}} = cnt
      ) do
    map_fn =
      fn %Model.BotCommand{:command => cmd, :description => desc} ->
        case is_binary(desc) do
          true ->
            "/#{cmd}@#{bot_username} - #{desc}"

          false ->
            "/#{cmd}@#{bot_username}"
        end
      end

    reply = ExGram.get_my_commands!() |> Enum.map(map_fn) |> Enum.join("\n")

    ExGram.send_message!(chat_id, reply)

    cnt
  end

  def handle(msg, cnt) do
    Logger.warning("Unknown message: #{inspect(msg)}")

    cnt
  end
end

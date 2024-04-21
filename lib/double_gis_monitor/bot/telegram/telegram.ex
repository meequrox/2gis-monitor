defmodule DoubleGisMonitor.Bot.Telegram do
  @bot :double_gis_monitor

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  require Logger

  alias DoubleGisMonitor.Bot.Telegram.Middleware
  alias DoubleGisMonitor.Event.Poller
  alias DoubleGisMonitor.Event.Processor
  alias DoubleGisMonitor.Database.Chat, as: DbChat
  alias DoubleGisMonitor.Database.Event
  alias DoubleGisMonitor.Database.Repo
  alias ExGram.Cnt
  alias ExGram.Error

  command("start", description: "Start polling events")
  command("stop", description: "Stop polling events")
  command("help", description: "Print the bot's help")
  command("info", description: "Print current service status")

  middleware(Middleware.IgnorePrivateMessages)

  def init(_opts) do
    Repo.transaction(fn -> init_in_transaction() end)
  end

  def bot(), do: @bot

  def handle(msg, %Cnt{:extra => %{:rejected => true} = cnt}) do
    Logger.warning("Message was rejected by middleware: #{inspect(msg)}")

    cnt
  end

  def handle({:command, "start@" <> _b, _msg}, cnt) do
    reply =
      "Now bot will perform the distribution of event updates on the 2GIS map in this chat."

    Repo.add_chat(cnt.update.message.chat.id, cnt.update.message.chat.title)

    answer(cnt, reply)
  end

  def handle({:command, "stop@" <> _b, _msg}, cnt) do
    reply =
      "Now bot will stop sending event updates on the 2GIS map in this chat."

    case Repo.get(DbChat, cnt.update.message.chat.id) do
      nil ->
        :ok

      chat ->
        Repo.delete_chat(chat)
    end

    answer(cnt, reply)
  end

  def handle({:command, "info@" <> _b, _msg}, cnt) do
    status =
      Agent.get(Poller, fn m -> m end)
      |> Map.merge(Agent.get(Processor, fn m -> m end))
      |> prepare_status(cnt)

    reply =
      "Active in this chat: #{status.active}\n" <>
        "City: #{status.city}\n" <>
        "Layers: #{status.layers}\n" <>
        "Interval: #{status.interval} seconds\n" <>
        "Events in database: #{status.events_count}\n" <>
        "Last database cleanup: #{status.last_cleanup} hours ago"

    answer(cnt, reply)
  end

  def handle({:command, "help@" <> _b, _msg}, cnt) do
    commands =
      for bc <- ExGram.get_my_commands!(),
          do: "/#{bc.command}@#{cnt.bot_info.username} - #{bc.description}"

    reply = Enum.join(commands, "\n")

    answer(cnt, reply)
  end

  def handle(msg, cnt) do
    Logger.warning("Unknown message: #{inspect(msg)}")

    cnt
  end

  defp init_in_transaction() do
    sticker = "CAACAgIAAxkBAAEq9l9mJAEHn6OZOrDIubls8uoa4dPkXgAChRYAAq4CEEo2ULUhfmVsyTQE"

    each_fn =
      fn c ->
        case ExGram.send_sticker(c.id, sticker) do
          {:ok, _msg} ->
            :ok

          {:error, %Error{:message => m}} ->
            message = m |> Jason.decode!() |> inspect()

            Logger.warning("#{c.title} (#{c.id}): #{message}")

            Repo.delete_chat(c)
        end
      end

    Enum.each(Repo.get_chats(), each_fn)
  end

  defp prepare_status(map, cnt) do
    map
    |> Map.put(:active, Repo.chat_exists?(cnt.update.message.chat.id) |> inspect())
    |> Map.put(:city, String.capitalize(map.city))
    |> Map.put(:layers, prepare_layers(map.layers))
    |> Map.put(:interval, trunc(map.interval / 1000))
    |> Map.put(:last_cleanup, DateTime.diff(DateTime.utc_now(), map.last_cleanup, :hour))
    |> Map.put(:events_count, Repo.aggregate(Event, :count))
  end

  defp prepare_layers(layers),
    do: layers |> String.slice(1..-2//1) |> String.replace("\"", "")
end

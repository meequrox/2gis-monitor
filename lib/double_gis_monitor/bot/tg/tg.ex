defmodule DoubleGisMonitor.Bot.Tg do
  @bot :double_gis_monitor

  use ExGram.Bot,
    name: @bot,
    setup_commands: true

  require Logger

  alias DoubleGisMonitor.Bot.Tg.Middleware
  alias DoubleGisMonitor.Worker.Poller
  alias DoubleGisMonitor.Worker.Processor
  alias DoubleGisMonitor.Db
  alias ExGram.Cnt
  alias ExGram.Error

  command("start", description: "Start polling events")
  command("stop", description: "Stop polling events")
  command("help", description: "Print the bot's help")
  command("info", description: "Print current service status")
  command("reset", description: "Reset database (clear all events)")

  middleware(Middleware.IgnorePm)

  def init(_opts) do
    Db.Repo.transaction(fn -> init_in_transaction() end)
  end

  def bot(), do: @bot

  def handle(msg, %Cnt{:extra => %{:rejected => true} = cnt}) do
    Logger.warning("Message was rejected by middleware: #{inspect(msg)}")

    cnt
  end

  def handle({:command, "start@" <> _b, _msg}, cnt) do
    reply =
      "Now bot will perform the distribution of event updates on the 2GIS map in this chat."

    Db.Utils.Chat.add(cnt.update.message.chat.id, cnt.update.message.chat.title)

    answer(cnt, reply)
  end

  def handle({:command, "stop@" <> _b, _msg}, cnt) do
    reply =
      "Now bot will stop sending event updates on the 2GIS map in this chat."

    case Db.Repo.get(Db.Chat, cnt.update.message.chat.id) do
      nil ->
        :ok

      chat ->
        Db.Utils.Chat.delete(chat)
    end

    answer(cnt, reply)
  end

  def handle({:command, "help@" <> _b, _msg}, cnt) do
    commands =
      for bc <- ExGram.get_my_commands!(),
          do: "/#{bc.command}@#{cnt.bot_info.username} - #{bc.description}"

    reply = Enum.join(commands, "\n")

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

  def handle({:command, "reset@" <> _b, msg}, cnt) do
    [reset_password: pass] = Application.fetch_env!(:double_gis_monitor, :tg_bot)

    if msg.text == pass do
      case Db.Utils.Event.reset() do
        {:ok, result} ->
          Logger.info("Reset events successfully: #{inspect(result)}")

          %{:id => poller_id} = DoubleGisMonitor.Worker.Poller.child_spec()

          Supervisor.terminate_child(DoubleGisMonitor.Application.Supervisor, poller_id)
          Supervisor.restart_child(DoubleGisMonitor.Application.Supervisor, poller_id)

        {:error, error} ->
          Logger.error("Events reset failed error: #{inspect(error)}")
      end
    end

    cnt
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

            Db.Utils.Chat.delete(c)
        end
      end

    Enum.each(Db.Utils.Chat.all(), each_fn)
  end

  defp prepare_status(map, cnt) do
    map
    |> Map.put(:active, Db.Utils.Chat.exists?(cnt.update.message.chat.id) |> inspect())
    |> Map.put(:city, String.capitalize(map.city))
    |> Map.put(:layers, prepare_layers(map.layers))
    |> Map.put(:interval, trunc(map.interval / 1000))
    |> Map.put(:last_cleanup, DateTime.diff(DateTime.utc_now(), map.last_cleanup, :hour))
    |> Map.put(:events_count, Db.Repo.aggregate(Db.Event, :count))
  end

  defp prepare_layers(layers),
    do: layers |> String.slice(1..-2//1) |> String.replace("\"", "")
end

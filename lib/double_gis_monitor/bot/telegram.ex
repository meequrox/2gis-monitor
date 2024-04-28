defmodule DoubleGisMonitor.Bot.Telegram do
  use Telegex.Polling.GenHandler

  @impl true
  def on_boot() do
    {:ok, true} = Telegex.delete_webhook()

    %Telegex.Polling.Config{
      interval: 1000,
      timeout: 1000,
      allowed_updates: ["message"]
    }
  end

  @impl true
  def on_init(_arg) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz, channel_id: channel_id] = Keyword.take(env, [:timezone, :channel_id])

    Process.sleep(100)

    {:ok, true} =
      Telegex.set_my_commands([
        %Telegex.Type.BotCommand{command: "/help", description: "Print all commands"},
        %Telegex.Type.BotCommand{command: "/info", description: "Print service status"},
        %Telegex.Type.BotCommand{
          command: "/reset",
          description: "Delete all events from database and channel"
        }
      ])

    datetime = tz |> DateTime.now() |> Calendar.strftime("%d.%m.%y %H:%M:%S")
    text = "Polling started at " <> datetime

    Process.sleep(100)
    {:ok, _message} = Telegex.send_message(channel_id, text)

    :ok
  end

  @impl true
  def on_update(%Telegex.Type.Update{
        :message =>
          %Telegex.Type.Message{
            :text => text,
            :chat => %Telegex.Type.Chat{:type => "channel", :id => update_channel_id} = chat
          } = message
      }) do
    env = Application.get_env(:double_gis_monitor, :dispatch, [])
    [channel_id: config_channel_id] = Keyword.take(env, [:channel_id])

    if config_channel_id === update_channel_id do
      case text do
        "/help" ->
          handle_command(:help, chat)

        "/info" ->
          handle_command(:info, chat)

        "/reset" ->
          handle_command(:reset, chat)

        _other ->
          Logger.info("Rejected unknown message: #{inspect(message)}")
      end
    else
      Logger.info("Rejected message from foreign channel: #{message}")
    end
  end

  @impl true
  def on_update(update) do
    Logger.info("Rejected update: #{inspect(update)}")
  end

  defp handle_command(:help, %Telegex.Type.Chat{:id => channel_id}) do
    {:ok, commands} = Telegex.get_my_commands()

    map_fun = fn %Telegex.Type.BotCommand{:command => cmd, :description => desc} ->
      cmd <> " - " <> desc
    end

    reply = commands |> Enum.map(map_fun) |> Enum.join("\n")

    Process.sleep(100)

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:info, %Telegex.Type.Chat{:id => channel_id}) do
    env = Application.get_env(:double_gis_monitor, :fetch, [])

    [city: city, layers: layers, interval: interval] =
      Keyword.take(env, [:city, :layers, :interval])

    status = %{
      city: String.capitalize(city),
      layers: layers |> String.slice(1..-2//1) |> String.replace("\"", ""),
      interval: trunc(interval / 1000),
      events_count: DoubleGisMonitor.Db.Repo.aggregate(DoubleGisMonitor.Db.Event, :count)
    }

    reply =
      "City: #{status.city}\n" <>
        "Layers: #{status.layers}\n" <>
        "Interval: #{status.interval} seconds\n" <>
        "Events in database: #{status.events_count}\n"

    Process.sleep(100)

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:reset, %Telegex.Type.Chat{:id => channel_id}) do
    # TODO: query and delete all linked messages
    # TODO: truncate table messages (transaction)
    # TODO: truncate table events (transaction)
    # {:ok, _chat} = DoubleGisMonitor.Db.Repo.transaction(fn -> reset() end)

    Process.sleep(100)

    case Telegex.send_message(channel_id, "Database cleaned") do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end
end

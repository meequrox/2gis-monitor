defmodule DoubleGisMonitor.Bot.Telegram do
  @moduledoc """
  Telegram bot that responds only to messages in a specific channel (set in the private project configuration).

  The module supports the usual principle of bot operation (command-response), but using the channel posts.
  The bot's functions will mainly be used by the dispatch module.
  """

  use Telegex.Polling.GenHandler

  @send_delay 1500

  @spec send_delay() :: integer()
  defmacro send_delay(), do: @send_delay

  @impl true
  def on_boot() do
    {:ok, true} = Telegex.delete_webhook()

    %Telegex.Polling.Config{
      interval: 5000,
      allowed_updates: ["channel_post"]
    }
  end

  @impl true
  def on_init(_arg) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [timezone: tz, channel_id: channel_id] = Keyword.take(env, [:timezone, :channel_id])

    Process.sleep(@send_delay)

    commands =
      [
        %Telegex.Type.BotCommand{command: "help", description: "Print all commands"},
        %Telegex.Type.BotCommand{command: "info", description: "Print service status"}
      ]

    {:ok, true} = Telegex.set_my_commands(commands)

    datetime = tz |> DateTime.now!(TimeZoneInfo.TimeZoneDatabase) |> Calendar.strftime("%H:%M:%S")
    text = "Bot started at " <> datetime <> "\n\n" <> commands_to_text(commands)

    Process.sleep(@send_delay)
    {:ok, _message} = Telegex.send_message(channel_id, text)

    :ok
  end

  @impl true
  def on_update(%Telegex.Type.Update{
        :channel_post =>
          %Telegex.Type.Message{
            :text => text,
            :chat => %Telegex.Type.Chat{:type => "channel", :id => update_channel_id} = chat
          } = message
      }) do
    env = Application.fetch_env!(:double_gis_monitor, :dispatch)
    [channel_id: config_channel_id] = Keyword.take(env, [:channel_id])

    if config_channel_id === update_channel_id do
      case text do
        "/help" ->
          handle_command(:help, chat)

        "/info" ->
          handle_command(:info, chat)

        _other ->
          Logger.info("Rejected unknown message: #{inspect(message)}")
      end
    else
      Logger.info("Rejected message from foreign channel: #{inspect(message)}")
    end
  end

  @impl true
  def on_update(update) do
    Logger.info("Rejected update: #{inspect(update)}")
  end

  defp handle_command(:help, %Telegex.Type.Chat{:id => channel_id}) do
    {:ok, commands} = Telegex.get_my_commands()

    reply = commands_to_text(commands)

    Process.sleep(@send_delay)

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:info, %Telegex.Type.Chat{:id => channel_id}) do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)

    [city: city, layers: layers, interval: interval] =
      Keyword.take(env, [:city, :layers, :interval])

    status = %{
      city: String.capitalize(city),
      layers: inspect(layers),
      interval: interval,
      events_count: DoubleGisMonitor.Db.Repo.aggregate(DoubleGisMonitor.Db.Event, :count)
    }

    reply =
      "City: #{status.city}\n" <>
        "Layers: #{status.layers}\n" <>
        "Interval: #{status.interval} seconds\n" <>
        "Events in database: #{status.events_count}\n"

    Process.sleep(@send_delay)

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp commands_to_text(commands) when is_list(commands) do
    map_fun =
      fn %Telegex.Type.BotCommand{:command => cmd, :description => desc} ->
        "/" <> cmd <> " - " <> desc
      end

    Enum.map_join(commands, "\n", map_fun)
  end
end

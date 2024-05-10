defmodule DoubleGisMonitor.Bot.Telegram do
  @moduledoc """
  Telegram bot that responds only to messages in a specific channel (set in the private project configuration).

  The module supports the usual principle of bot operation (command-response), but using the channel posts.
  The bot's functions will mainly be used by the dispatch module.
  """

  use Telegex.Polling.GenHandler

  alias DoubleGisMonitor.RateLimiter
  alias DoubleGisMonitor.Db, as: Database
  alias Telegex.Type, as: TgType

  @impl true
  def on_boot() do
    {:ok, true} = Telegex.delete_webhook()
    RateLimiter.sleep_after(:ok, __MODULE__, :request)

    %Telegex.Polling.Config{
      interval: 5000,
      allowed_updates: ["channel_post"]
    }
  end

  @impl true
  def on_init(_arg) do
    commands =
      [
        %TgType.BotCommand{command: "help", description: "Print all commands"},
        %TgType.BotCommand{command: "info", description: "Print service status"}
      ]

    {:ok, true} = Telegex.set_my_commands(commands)
    RateLimiter.sleep_after(:ok, __MODULE__, :request)
  end

  @impl true
  def on_update(%TgType.Update{
        :channel_post =>
          %TgType.Message{
            :text => text,
            :chat => %TgType.Chat{:type => "channel", :id => update_channel_id} = chat
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

  defp handle_command(:help, %TgType.Chat{:id => channel_id}) do
    {:ok, commands} = Telegex.get_my_commands()
    RateLimiter.sleep_after(:ok, __MODULE__, :request)

    reply = commands_to_text(commands)

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        RateLimiter.sleep_after(:ok, __MODULE__, :send)

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:info, %TgType.Chat{:id => channel_id}) do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)

    [city: city, layers: layers, interval: interval] =
      Keyword.take(env, [:city, :layers, :interval])

    status = %{
      city: String.capitalize(city),
      layers: inspect(layers),
      interval: interval,
      events_count: Database.Repo.aggregate(Database.Event, :count)
    }

    reply =
      "City: #{status.city}\n" <>
        "Layers: #{status.layers}\n" <>
        "Interval: #{status.interval} seconds\n" <>
        "Events in database: #{status.events_count}\n"

    case Telegex.send_message(channel_id, reply) do
      {:ok, _message} ->
        RateLimiter.sleep_after(:ok, __MODULE__, :send)

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp commands_to_text(commands) when is_list(commands) do
    map_fun =
      fn %TgType.BotCommand{:command => cmd, :description => desc} ->
        "/" <> cmd <> " - " <> desc
      end

    Enum.map_join(commands, "\n", map_fun)
  end
end

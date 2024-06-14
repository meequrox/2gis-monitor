defmodule DoubleGisMonitor.Bot.Telegram do
  @moduledoc """
  Telegram bot that responds only to messages in a specific channel (set in the private project configuration).

  The module supports the usual principle of bot operation (command-response), but using the channel posts.
  The bot's functions will mainly be used by the dispatch module.
  """

  use Telegex.Polling.GenHandler

  alias DoubleGisMonitor.{RateLimiter, Database}
  alias DoubleGisMonitor.Pipeline.WorkerManager
  alias Telegex.Type, as: TgType

  @impl true
  def on_boot() do
    {:ok, true} =
      Telegex.delete_webhook()
      |> RateLimiter.sleep_after(__MODULE__, :request)

    %Telegex.Polling.Config{
      interval: 5000,
      allowed_updates: ["channel_post"]
    }
  end

  @impl true
  def on_init(_arg) do
    {:ok, true} =
      [
        %TgType.BotCommand{command: "help", description: "Print all commands"},
        %TgType.BotCommand{command: "info", description: "Print service status"}
      ]
      |> Telegex.set_my_commands()
      |> RateLimiter.sleep_after(__MODULE__, :request)

    :ok
  end

  @impl true
  def on_update(%TgType.Update{
        :channel_post =>
          %TgType.Message{
            :text => text,
            :chat => %TgType.Chat{:type => "channel", :id => update_channel_id} = chat
          } = message
      }) do
    {:ok, config_channel_id} =
      :double_gis_monitor |> Application.fetch_env!(:dispatch) |> Keyword.fetch(:channel_id)

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
    {:ok, commands} = Telegex.get_my_commands() |> RateLimiter.sleep_after(__MODULE__, :request)

    case Telegex.send_message(channel_id, commands_to_text(commands)) do
      {:ok, _message} ->
        RateLimiter.sleep_after(:ok, __MODULE__, :send)

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:info, %TgType.Chat{:id => channel_id}) do
    # TODO: get from one of Pipeline module
    [city: city, layers: layers] =
      :double_gis_monitor
      |> Application.fetch_env!(:fetch)
      |> Keyword.take([:city, :layers])

    {:ok, runs_count} = WorkerManager.get_count()
    {:ok, last_result} = WorkerManager.get_last_result()
    {:ok, interval} = WorkerManager.get_interval()
    # TODO: Get last result timestamp

    reply =
      [
        {"Service",
         """
         City: #{String.capitalize(city)}
         Layers: #{inspect(layers)}
         """},
        {"Worker",
         """
         Runs count: #{runs_count}
         Last result: #{inspect(last_result)}
         Interval: #{interval} seconds
         """},
        {"Database",
         """
         Events count: #{Database.Repo.aggregate(Database.Event, :count)}
         """}
      ]
      |> Enum.map_join(
        "\n",
        fn {section, props} ->
          "<b>" <> section <> "</b>\n" <> Telegex.Tools.safe_html(props)
        end
      )

    case Telegex.send_message(channel_id, reply, parse_mode: "HTML") do
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

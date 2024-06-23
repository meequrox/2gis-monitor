defmodule DoubleGisMonitor.Bot.Telegram do
  @moduledoc """
  Telegram bot that responds only to messages in a specific channel (set in the private project configuration).

  The module supports the usual principle of bot operation (command-response), but using the channel posts.
  """

  use Telegex.Polling.GenHandler

  alias DoubleGisMonitor.RateLimiter
  alias DoubleGisMonitor.Bot.Telegram.CommandHandler

  @impl true
  def on_boot() do
    {:ok, true} = Telegex.delete_webhook()

    RateLimiter.sleep(:telegram, :request)

    %Telegex.Polling.Config{
      interval: 5000,
      allowed_updates: ["channel_post"]
    }
  end

  @impl true
  def on_init(_opts) do
    {:ok, true} =
      [
        %Telegex.Type.BotCommand{command: "help", description: "Print all commands"},
        %Telegex.Type.BotCommand{command: "info", description: "Print service status"}
      ]
      |> Telegex.set_my_commands()

    RateLimiter.sleep(:telegram, :request)
  end

  @impl true
  def on_update(%{
        channel_post: %{text: text, chat: %{type: "channel", id: update_channel_id} = chat}
      }) do
    {:ok, %{channel_id: config_channel_id}} = WorkerManager.get_stages_opts()

    if config_channel_id == update_channel_id do
      CommandHandler.handle(text, chat)
    else
      Logger.warning("Rejected message from foreign channel #{update_channel_id}")
    end
  end

  @impl true
  def on_update(update) do
    Logger.warning("Rejected update: #{inspect(update)}")
  end
end

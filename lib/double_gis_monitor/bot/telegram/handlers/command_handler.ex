defmodule DoubleGisMonitor.Bot.Telegram.CommandHandler do
  require Logger

  alias DoubleGisMonitor.Bot.Telegram.{HelpTemplate, InfoTemplate}
  alias DoubleGisMonitor.Database.EventHandler
  alias DoubleGisMonitor.Pipeline.WorkerManager
  alias DoubleGisMonitor.RateLimiter

  def handle("/help", %{id: channel_id}) do
    {:ok, commands} = Telegex.get_my_commands()
    RateLimiter.sleep(:telegram, :request)

    text = HelpTemplate.render(commands)

    case Telegex.send_message(channel_id, text) do
      {:ok, _message} ->
        RateLimiter.sleep(:telegram, :send)

      {:error, error} ->
        Logger.error("Failed to send help to #{channel_id}: #{inspect(error)}")
    end
  end

  def handle("/info", %{id: channel_id}) do
    {:ok, runs_count} = WorkerManager.get_count()
    {:ok, last_result} = WorkerManager.get_last_result()
    {:ok, interval} = WorkerManager.get_interval()
    {:ok, %{city: city, layers: layers}} = WorkerManager.get_stages_opts()
    events_count = EventHandler.count()

    text =
      %{
        runs: runs_count,
        last_result: last_result,
        interval: interval,
        city: city,
        layers: layers,
        events: events_count
      }
      |> InfoTemplate.render()

    case Telegex.send_message(channel_id, text, parse_mode: "HTML") do
      {:ok, _message} ->
        RateLimiter.sleep(:telegram, :send)

      {:error, error} ->
        Logger.error("Failed to send info to #{channel_id}: #{inspect(error)}")
    end
  end

  def handle(unknown, chat) do
    Logger.info("Rejected unknown command #{unknown} from #{inspect(chat)}")
  end
end

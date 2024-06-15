defmodule DoubleGisMonitor.Bot.Telegram do
  @moduledoc """
  Telegram bot that responds only to messages in a specific channel (set in the private project configuration).

  The module supports the usual principle of bot operation (command-response), but using the channel posts.
  """

  use Telegex.Polling.GenHandler

  alias DoubleGisMonitor.{RateLimiter, Database}
  alias DoubleGisMonitor.Pipeline.WorkerManager

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
  def on_init(_opts) do
    {:ok, true} =
      [
        %Telegex.Type.BotCommand{command: "help", description: "Print all commands"},
        %Telegex.Type.BotCommand{command: "info", description: "Print service status"}
      ]
      |> Telegex.set_my_commands()
      |> RateLimiter.sleep_after(__MODULE__, :request)

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
    {:ok, %{dispatch: %{channel_id: config_channel_id}}} = WorkerManager.get_stages_opts()

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
    {:ok, commands} =
      Telegex.get_my_commands()
      |> RateLimiter.sleep_after(__MODULE__, :request)

    case Telegex.send_message(channel_id, commands_to_text(commands)) do
      {:ok, _message} ->
        RateLimiter.sleep_after(:ok, __MODULE__, :send)

      {:error, error} ->
        Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
    end
  end

  defp handle_command(:info, %Telegex.Type.Chat{:id => channel_id}) do
    # TODO: Get last result timestamp
    with {:ok, runs_count} <- WorkerManager.get_count(),
         {:ok, last_result} <- WorkerManager.get_last_result(),
         {:ok, interval} <- WorkerManager.get_interval(),
         {:ok, %{fetch: %{city: city, layers: layers}}} <- WorkerManager.get_stages_opts() do
      reply =
        %{
          city: city,
          layers: layers,
          count: runs_count,
          last_result: last_result,
          interval: interval
        }
        |> render_reply(:info)

      case Telegex.send_message(channel_id, reply, parse_mode: "HTML") do
        {:ok, _message} ->
          RateLimiter.sleep_after(:ok, __MODULE__, :send)

        {:error, error} ->
          Logger.error("Failed to send reply to #{channel_id}: #{inspect(error)}")
      end
    else
      {:error, error} ->
        Logger.error("Failed to get info for /info reply: #{inspect(error)}")
    end
  end

  defp render_reply(
         %{
           city: city,
           layers: layers,
           count: count,
           last_result: last_result,
           interval: interval
         },
         :info
       )
       when is_binary(city) and is_integer(count) and is_integer(interval) do
    [
      {"Service",
       [
         {"City", String.capitalize(city)},
         {"Layers", inspect(layers)}
       ]},
      {"Worker",
       [
         {"Runs count", Integer.to_string(count)},
         {"Interval", Integer.to_string(interval)},
         {"Last result", inspect(last_result), :code}
       ]},
      {"Database",
       [
         {"Events count",
          Database.Event |> Database.Repo.aggregate(:count) |> Integer.to_string()}
       ]}
    ]
    |> Enum.map_join(
      "\n",
      fn {category, prop_list} ->
        props_str =
          Enum.reduce(prop_list, "", fn
            {prop_name, prop_value}, acc ->
              acc <> "#{prop_name}: #{Telegex.Tools.safe_html(prop_value)}\n"

            {prop_name, prop_value, :code}, acc ->
              acc <> "#{prop_name}: <code>#{prop_value}</code>\n"
          end)

        """
        <b># #{category}</b>
        #{props_str}
        """
      end
    )
  end

  defp commands_to_text(commands) when is_list(commands) do
    Enum.map_join(commands, "\n", fn
      %{:command => cmd, :description => desc} ->
        "/" <> cmd <> " - " <> desc
    end)
  end
end

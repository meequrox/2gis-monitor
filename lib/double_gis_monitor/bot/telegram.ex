defmodule DoubleGisMonitor.Bot.Telegram do
  use Telegex.Polling.GenHandler

  import Ecto.Query, only: [from: 2]

  @impl true
  def on_boot() do
    {:ok, true} = Telegex.delete_webhook()

    %Telegex.Polling.Config{
      interval: 1000,
      timeout: 1000,
      allowed_updates: ["message"]
    }
  end

  # TODO: code check
  # TODO: log errors
  # TODO: catch errors

  # TODO: set commands on init

  @impl true
  def on_init(_arg) do
    file_id = "CAACAgIAAxkBAAErELdmKrow9_NVH6gcudBTW74_YVNoXAAC0xcAArpnmElpOuY9xD_-hzQE"

    each_fun =
      fn %DoubleGisMonitor.Db.Chat{:id => id} = chat ->
        Process.sleep(100)

        case Telegex.send_sticker(id, file_id) do
          {:ok, _message} ->
            {:ok, id}

          {:error, %Telegex.Error{:error_code => 403}} ->
            Logger.info("Deleting chat #{id} from DB.")
            {:ok, _chat} = DoubleGisMonitor.Db.Repo.transaction(fn -> delete_chat(chat) end)
            {:ok, id}

          {:error, other} ->
            Logger.error("Failed to send boot message to #{id}: #{inspect(other)}.")
            {:error, id}
        end
      end

    DoubleGisMonitor.Db.Chat
    |> DoubleGisMonitor.Db.Repo.all()
    |> Enum.each(each_fun)
  end

  @impl true
  def on_update(%Telegex.Type.Update{
        :message => %Telegex.Type.Message{
          :text => text,
          :chat => %Telegex.Type.Chat{:type => "private"} = chat
        }
      }) do
    # TODO: get password from config
    password = "hello_world"

    case text do
      "/start " <> ^password ->
        handle_command(:start, chat)

      "/reset " <> ^password ->
        handle_command(:reset, chat)

      "/info" ->
        handle_command(:info, chat)

      "/stop" ->
        handle_command(:stop, chat)

      "/help" ->
        handle_command(:help, chat)

      _other ->
        handle_command(:unknown, chat)
    end
  end

  @impl true
  def on_update(update) do
    Logger.info("Rejected update: #{inspect(update)}")
  end

  defp handle_command(:start, %Telegex.Type.Chat{:id => chat_id, :username => username}) do
    {:ok, _chat} = DoubleGisMonitor.Db.Repo.transaction(fn -> add_chat(chat_id, username) end)

    reply = "Polling started"

    Process.sleep(100)

    case Telegex.send_message(chat_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{chat_id}: #{inspect(error)}")
        :ok
    end
  end

  defp handle_command(:reset, %Telegex.Type.Chat{:id => chat_id}) do
    # TODO: truncate table
    # {:ok, _chat} = DoubleGisMonitor.Db.Repo.transaction(fn -> reset() end)

    reply = "Database cleaned"

    Process.sleep(100)

    case Telegex.send_message(chat_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{chat_id}: #{inspect(error)}")
        :ok
    end
  end

  defp handle_command(:info, %Telegex.Type.Chat{:id => chat_id}) do
    env = Application.get_env(:double_gis_monitor, :fetch, [])

    status =
      case Keyword.take(env, [:city, :layers, :interval]) do
        [city: city, layers: layers, interval: interval] ->
          query = from(c in "chats", where: c.id == ^chat_id)

          %{
            active: DoubleGisMonitor.Db.Repo.exists?(query) |> inspect(),
            city: String.capitalize(city),
            layers: layers |> String.slice(1..-2//1) |> String.replace("\"", ""),
            interval: trunc(interval / 1000),
            events_count: DoubleGisMonitor.Db.Repo.aggregate(DoubleGisMonitor.Db.Event, :count)
          }

        _other ->
          Logger.error("There is no configuration for fetching. See config/fetch.exs file.")

          %{
            active: "unknown",
            city: "unknown",
            layers: "unknown",
            interval: "unknown",
            events_count: "unknown"
          }
      end

    reply =
      "Polling started: #{status.active}\n" <>
        "City: #{status.city}\n" <>
        "Layers: #{status.layers}\n" <>
        "Interval: #{status.interval} seconds\n" <>
        "Events in database: #{status.events_count}\n"

    Process.sleep(100)

    case Telegex.send_message(chat_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{chat_id}: #{inspect(error)}")
        :ok
    end
  end

  defp handle_command(:stop, %Telegex.Type.Chat{:id => chat_id}) do
    {:ok, _chat} =
      case DoubleGisMonitor.Db.Repo.get(DoubleGisMonitor.Db.Chat, chat_id) do
        nil ->
          {:ok, %DoubleGisMonitor.Db.Chat{id: chat_id, username: ""}}

        chat ->
          DoubleGisMonitor.Db.Repo.transaction(fn -> delete_chat(chat) end)
      end

    reply = "Polling stopped"

    Process.sleep(100)

    case Telegex.send_message(chat_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{chat_id}: #{inspect(error)}")
        :ok
    end
  end

  defp handle_command(:help, %Telegex.Type.Chat{:id => chat_id}) do
    {:ok, commands} = Telegex.get_my_commands()

    map_fun = fn %Telegex.Type.BotCommand{:command => cmd, :description => desc} ->
      cmd <> " - " <> desc
    end

    reply = commands |> Enum.map(map_fun) |> Enum.join("\n")

    Process.sleep(100)

    case Telegex.send_message(chat_id, reply) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.error("Failed to send reply to #{chat_id}: #{inspect(error)}")
        :ok
    end
  end

  defp handle_command(:unknown, message) do
    Logger.info("Rejected message: #{inspect(message)}")
  end

  defp add_chat(id, username) do
    result =
      case DoubleGisMonitor.Db.Repo.get(DoubleGisMonitor.Db.Chat, id) do
        nil ->
          DoubleGisMonitor.Db.Repo.insert(%DoubleGisMonitor.Db.Chat{id: id, username: username})

        db_chat ->
          db_chat
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_change(:username, username)
          |> DoubleGisMonitor.Db.Repo.update()
      end

    case result do
      {:ok, struct} -> {:ok, struct}
      {:error, changeset} -> DoubleGisMonitor.Db.Repo.rollback(changeset)
    end
  end

  defp delete_chat(chat) when is_map(chat) do
    case DoubleGisMonitor.Db.Repo.delete(chat, returning: false) do
      {:ok, _struct} -> {:ok, chat}
      {:error, changeset} -> DoubleGisMonitor.Db.Repo.rollback(changeset)
    end
  end
end

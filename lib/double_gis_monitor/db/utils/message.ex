defmodule DoubleGisMonitor.Db.Utils.Message do
  require Logger

  alias DoubleGisMonitor.Db

  def get(uuid) do
    case Db.Repo.get(Db.Message, uuid) do
      nil -> []
      s -> s
    end
  end

  def insert_or_update(uuid, chat_id, messages)
      when is_binary(uuid) and is_integer(chat_id) and is_list(messages) do
    case Db.Repo.get(Db.Message, uuid) do
      # TODO: value `[[340]]` for `DoubleGisMonitor.Db.Message.messages` in `insert` does not match type {:array, :integer}
      nil ->
        Db.Repo.insert(%Db.Message{uuid: uuid, chats: [chat_id], messages: [messages]})

      db_message ->
        changeset =
          case Enum.find_index(db_message.chats, fn id -> id === chat_id end) do
            nil ->
              db_message
              |> Ecto.Changeset.change(chats: [chat_id | db_message.chats])
              |> Ecto.Changeset.change(messages: [messages | db_message.messages])

            i ->
              new_list = Enum.concat([db_message.messages, messages])
              new_messages = List.update_at(db_message.messages, i, fn _list -> new_list end)

              Ecto.Changeset.change(db_message, messages: new_messages)
          end

        Logger.info("Changeset #{changeset}")
        Db.Repo.update(changeset)
    end
  end

  def delete(uuid) do
    Db.Repo.delete(%Db.Message{uuid: uuid})
  end

  def reset() do
    # TODO: delete messages from chats
    table = Db.Message.__schema__(:source)

    Db.Repo.query("TRUNCATE #{table}", [])
  end
end

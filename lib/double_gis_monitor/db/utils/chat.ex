defmodule DoubleGisMonitor.Db.Utils.Chat do
  import Ecto.Query, only: [from: 2]

  alias DoubleGisMonitor.Db

  def add(id, title) do
    case Db.Repo.get(Db.Chat, id) do
      nil ->
        Db.Repo.insert(%Db.Chat{id: id, title: title})

      db_chat ->
        db_chat
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:title, title)
        |> Db.Repo.update()
    end
  end

  def all(), do: Db.Repo.all(Db.Chat)

  def exists?(id) do
    query = from(c in "chats", where: c.id == ^id)

    Db.Repo.exists?(query)
  end

  def delete(%{:id => id, :title => title}) do
    case Db.Repo.delete(%Db.Chat{id: id, title: title}, returning: false) do
      {:ok, _} ->
        :ok

      {:error, c} ->
        if Db.Repo.in_transaction?() do
          Db.Repo.rollback(c)
        end

        :error
    end
  end
end

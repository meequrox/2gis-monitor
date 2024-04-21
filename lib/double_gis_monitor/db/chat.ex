defmodule DoubleGisMonitor.Db.Chat do
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}

  schema "chats" do
    field(:title, :string)
  end
end

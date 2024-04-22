defmodule DoubleGisMonitor.Db.Message do
  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "messages" do
    field(:chats, {:array, :integer})
    field(:messages, {:array, :integer})
  end
end

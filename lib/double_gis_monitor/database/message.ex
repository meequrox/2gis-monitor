defmodule DoubleGisMonitor.Database.TelegramMessage do
  @moduledoc """
  Struct that represent a ID list of Telegram messages being sent by dispatcher module.

  If a message has a type caption, its list can contain from 1 to N members. This number is not really limited, but in most cases it will be less than 10.
  If a message has a type text, its list will only contain 1 ID.
  """

  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "telegram_messages" do
    field(:type, :string)
    field(:count, :integer)
    field(:list, {:array, :integer})
  end
end

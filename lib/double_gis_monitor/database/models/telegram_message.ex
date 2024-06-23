defmodule DoubleGisMonitor.Database.TelegramMessage do
  @moduledoc """
  Model that represent a ID list of Telegram messages being sent by dispatcher module.

  If a message has a type caption, its list can contain from 1 to N members. This number is not really limited, but in most cases it will be less than 10.
  If a message has a type text, its list will only contain 1 ID.
  """

  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "telegram_messages" do
    field(:type, :string)
    field(:channel, :integer)
    field(:list, {:array, :integer})
    field(:timezone, :string)

    timestamps()
  end
end

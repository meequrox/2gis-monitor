defmodule DoubleGisMonitor.Db.Message do
  @moduledoc """
  TODO: moduledoc
  """

  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "messages" do
    field(:type, :string)
    field(:count, :integer)
    field(:list, {:array, :integer})
  end
end

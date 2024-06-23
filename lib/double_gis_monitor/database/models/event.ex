defmodule DoubleGisMonitor.Database.Event do
  @moduledoc """
  A model representing a 2GIS event processed by the corresponding module.
  """

  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "events" do
    field(:timestamp, :integer)
    field(:type, :string)
    field(:username, :string)
    field(:geo, {:array, :float})
    field(:comment, :string)
    field(:likes, :integer)
    field(:dislikes, :integer)
    field(:images_count, :integer)
    field(:images_list, {:array, :string})
    field(:city, :string)

    timestamps()
  end
end

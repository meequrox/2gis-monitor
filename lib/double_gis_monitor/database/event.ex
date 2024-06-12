defmodule DoubleGisMonitor.Database.Event do
  @moduledoc """
  A struct representing a 2GIS event processed by the corresponding module.
  """

  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "events" do
    field(:timestamp, :integer)
    field(:type, :string)
    field(:username, :string)
    field(:coordinates, {:map, :float})
    field(:comment, :string)
    field(:feedback, {:map, :integer})
    field(:attachments, :map)
  end
end

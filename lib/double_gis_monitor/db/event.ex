defmodule DoubleGisMonitor.Db.Event do
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

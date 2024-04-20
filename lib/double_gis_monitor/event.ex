defmodule DoubleGisMonitor.Event do
  use Ecto.Schema

  @primary_key {:uuid, :string, autogenerate: false}

  schema "events" do
    field(:timestamp, :integer)
    field(:type, :string)
    field(:username, :string)
    field(:coordinates, {:map, :float})
    field(:comment, :string)
    field(:likes, :integer)
    field(:dislikes, :integer)
    field(:attachments_count, :integer)
    field(:attachments_list, {:array, :string})
  end
end

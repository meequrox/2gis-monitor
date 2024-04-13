defmodule DoubleGisMonitor.Event do
  use Ecto.Schema

  schema "events" do
    field(:uuid, :string, primary_key: true)
    field(:datetime, :utc_datetime)
    field(:type, :string)
    field(:username, :string)
    field(:coordinates, {:map, :float})
    field(:likes, :integer)
    field(:dislikes, :integer)
  end
end

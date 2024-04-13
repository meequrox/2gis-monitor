defmodule DoubleGisMonitor.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change() do
    create table(:events) do
      add(:uuid, :string, primary_key: true)
      add(:datetime, :utc_datetime)
      add(:type, :string)
      add(:username, :string)
      add(:coordinates, {:map, :float})
      add(:likes, :integer)
      add(:dislikes, :integer)
    end
  end
end

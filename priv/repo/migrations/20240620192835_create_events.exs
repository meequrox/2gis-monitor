defmodule DoubleGisMonitor.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change() do
    create table(:events, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:timestamp, :integer)
      add(:type, :string)
      add(:username, :string)
      add(:geo, {:array, :float})
      add(:comment, :string)
      add(:likes, :integer)
      add(:dislikes, :integer)
      add(:images_count, :integer)
      add(:images_list, {:array, :string})
      add(:city, :string)

      timestamps()
    end
  end
end

defmodule DoubleGisMonitor.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change() do
    create table(:events, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:datetime, :utc_datetime)
      add(:type, :string)
      add(:username, :string)
      add(:coordinates, {:map, :float})
      add(:comment, :string)
      add(:likes, :integer)
      add(:dislikes, :integer)
      add(:attachments_count, :integer)
      add(:attachments_list, {:array, :string})
    end
  end
end

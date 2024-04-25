defmodule DoubleGisMonitor.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change() do
    create table(:events, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:timestamp, :integer)
      add(:type, :string)
      add(:username, :string)
      add(:coordinates, {:map, :float})
      add(:comment, :string)
      add(:feedback, {:map, :integer})
      add(:attachments, :map)
    end
  end
end

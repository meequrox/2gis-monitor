defmodule DoubleGisMonitor.Db.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change() do
    create table(:messages, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:chats, {:array, :bigint})
      add(:messages, {:array, :bigint})
    end
  end
end

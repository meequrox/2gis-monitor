defmodule DoubleGisMonitor.Db.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change() do
    create table(:chats, primary_key: false) do
      add(:id, :bigint, primary_key: true)
      add(:username, :string)
    end
  end
end

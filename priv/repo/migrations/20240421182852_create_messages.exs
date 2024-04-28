defmodule DoubleGisMonitor.Db.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change() do
    create table(:messages, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:type, :string)
      add(:count, :integer)
      add(:list, {:array, :bigint})
    end
  end
end

defmodule DoubleGisMonitor.Database.Repo.Migrations.CreateTelegramMessages do
  use Ecto.Migration

  def change() do
    create table(:telegram_messages, primary_key: false) do
      add(:uuid, :string, primary_key: true)
      add(:type, :string)
      add(:channel, :bigint)
      add(:list, {:array, :bigint})
      add(:timezone, :string)

      timestamps()
    end
  end
end

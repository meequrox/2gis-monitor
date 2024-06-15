defmodule DoubleGisMonitor.Database.Repo.Migrations.RenameMessages do
  use Ecto.Migration

  def change do
    rename table(:messages), to: table(:telegram_messages)
  end
end

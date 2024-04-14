defmodule DoubleGisMonitor.Repo.Migrations.RenameTimestamp do
  use Ecto.Migration

  def change() do
    rename(table("events"), :timestamp, to: :datetime)
  end
end

defmodule DoubleGisMonitor.Db.Repo do
  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres
end

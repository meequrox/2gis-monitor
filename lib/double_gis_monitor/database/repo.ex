defmodule DoubleGisMonitor.Database.Repo do
  @moduledoc """
  DoubleGisMonitor database
  """

  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres
end

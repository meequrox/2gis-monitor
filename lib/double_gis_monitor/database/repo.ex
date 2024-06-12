defmodule DoubleGisMonitor.Database.Repo do
  @moduledoc """
  Primary repo containing tables:
  - events
  - messages
  """

  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres
end

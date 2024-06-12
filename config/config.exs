import Config
timezone_db =
  case :os.type() do
    {:unix, _name} -> Zoneinfo.TimeZoneDatabase
    {:win32, _name} -> Tz.TimeZoneDatabase
  end

config(:double_gis_monitor,
  ecto_repos: [DoubleGisMonitor.Db.Repo]
)

config(:double_gis_monitor, :env, config_env())

config(:telegex, caller_adapter: {HTTPoison, [recv_timeout: 5 * 1000]})

config(:elixir, :time_zone_database, timezone_db)

config(:logger, :console,
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa],
  level: :info,
  colors: [info: :light_green]
)

import_config("runtime.exs")

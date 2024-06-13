import Config

env = config_env()

timezone_db =
  case :os.type() do
    {:unix, _name} -> Zoneinfo.TimeZoneDatabase
    {:win32, _name} -> Tz.TimeZoneDatabase
  end

logger_shared_opts = [
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa]
]

logger_file_opts =
  [
    truncate: :infinity,
    rotate: %{max_bytes: 104_857_600, keep: 3},
    max_file_num: 3
  ] ++ logger_shared_opts

logger_file_dir = "log"

config(:double_gis_monitor,
  ecto_repos: [DoubleGisMonitor.Database.Repo]
)

config(:double_gis_monitor, :env, env)

config(:telegex, caller_adapter: {HTTPoison, [recv_timeout: 5 * 1000]})

config(:elixir, :time_zone_database, timezone_db)

config(
  :logger,
  :console,
  [
    level: :info,
    colors: [info: :light_green]
  ] ++ logger_shared_opts
)

config(
  :logger,
  :debug_log,
  [
    level: :debug,
    path: Path.join(logger_file_dir, "debug.log")
  ] ++ logger_file_opts
)

config(
  :logger,
  :info_log,
  [
    level: :info,
    path: Path.join(logger_file_dir, "info.log")
  ] ++ logger_file_opts
)

config(
  :logger,
  :error_log,
  [
    level: :error,
    path: Path.join(logger_file_dir, "error.log")
  ] ++ logger_file_opts
)

import_config("#{env}.exs")
import_config("runtime.exs")

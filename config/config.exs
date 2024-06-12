import Config

env = config_env()

timezone_db =
  case :os.type() do
    {:unix, _name} -> Zoneinfo.TimeZoneDatabase
    {:win32, _name} -> Tz.TimeZoneDatabase
  end

log_opts = %{
  dir: "log",
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa],
  truncate: :infinity,
  rotate: %{max_bytes: 104_857_600, keep: 3}
}

config(:double_gis_monitor,
  ecto_repos: [DoubleGisMonitor.Database.Repo]
)

config(:double_gis_monitor, :env, env)

config(:telegex, caller_adapter: {HTTPoison, [recv_timeout: 5 * 1000]})

config(:elixir, :time_zone_database, timezone_db)

config(:logger, :console,
  format: log_opts.format,
  metadata: log_opts.metadata,
  level: :info,
  colors: [info: :light_green]
)

# BUG: Log rotating does not work

config(:logger, :debug_log,
  format: log_opts.format,
  metadata: log_opts.metadata,
  truncate: log_opts.truncate,
  rotate: log_opts.rotate,
  level: :debug,
  path: Path.join(log_opts.dir, "debug.log")
)

config(:logger, :info_log,
  format: log_opts.format,
  metadata: log_opts.metadata,
  truncate: log_opts.truncate,
  rotate: log_opts.rotate,
  level: :info,
  path: Path.join(log_opts.dir, "info.log")
)

config(:logger, :error_log,
  format: log_opts.format,
  metadata: log_opts.metadata,
  truncate: log_opts.truncate,
  rotate: log_opts.rotate,
  level: :error,
  path: Path.join(log_opts.dir, "error.log")
)

import_config("#{env}.exs")
import_config("runtime.exs")

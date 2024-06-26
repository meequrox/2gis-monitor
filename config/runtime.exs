import Config

# vv Project DATABASE configuration vv
# These settings match the default Postgres configuration (except for the password),
#                                   so they do not need to be changed unnecessarily.
# The default configuration can be changed by setting these environment variables when starting the application:
#  POSTGRES_DB - database name
#  POSTGRES_USER - database user
#  POSTGRES_USER - user password
#  DGM_POSTGRES_HOSTNAME - host where the Postgres instance is running
#  DGM_POSTGRES_PORT - port that the Postgres instance listens to
config(:double_gis_monitor, DoubleGisMonitor.Db.Repo,
  database: System.get_env("POSTGRES_DB", "double_gis_monitor_repo"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("DGM_POSTGRES_HOSTNAME", "localhost"),
  port: System.get_env("DGM_POSTGRES_PORT", "5432") |> String.to_integer(),
  log: :info
)

# ^^ Project DATABASE configuration ^^

# vv Project TIMEZONE configuration vv
# This time zone will be used when constructing a message to be sent to the Telegram channel.
# The default is Moscow, you can change this by setting the DGM_TIMEZONE environment variable when starting the application.
config(:double_gis_monitor, :dispatch, timezone: System.get_env("DGM_TIMEZONE", "Europe/Moscow"))
# ^^ Project TIMEZONE configuration ^^

# vv Project FETCHER configuration vv
# These settings affect what information will be received from 2GIS servers.
# The default configuration can be changed by setting these environment variables when starting the application:
#  DGM_CITY - city for which events on the map will be received.
#             Availability can be checked using https://2gis.ru/<YOUR_CITY> URL.
#  DGM_LAYERS - list of event types that will be requested from the server, separated by commas without spaces.
#               Known event types: camera, crash, roadwork, restriction, comment, other.
#  DGM_INTERVAL - interval in seconds at which the event processing pipeline will start.
# It is not recommended to set the interval value below 600 seconds.
# In this case, if there is a large number of events received (>190),
#   the next pipeline will start running before the old one finishes.
# This will not lead to errors, but the actual interval will be shifted upward.
default_layers = "crash,roadwork,restriction,comment,other"

config(:double_gis_monitor, :fetch,
  city: System.get_env("DGM_CITY", "Moscow"),
  layers: System.get_env("DGM_LAYERS", default_layers) |> String.split(",", trim: true),
  interval: System.get_env("DGM_INTERVAL", "600") |> String.to_integer()
)

# ^^ Project FETCHER configuration ^^

# vv Project BOT configuration vv
# There is no valid default configuration for bot.
# You NEED to change it by setting these environment variables when starting the application:
#  DGM_TG_TOKEN - app api_hash from https://my.telegram.org/apps
#  DGM_TG_CHANNEL - ID of the channel to which the bot will send messages.
#                   The bot must be an administrator and have the right to send messages.
#                   Other permissions can be disabled.
# Examples:
#  DGM_TG_TOKEN=7055549111:ANBG4v5I-f9f5MaZ_1gv0X8Dx8-_L0lHKKL
#  DGM_TG_CHANNEL=-1008111453999
config(:telegex,
  token: System.get_env("DGM_TG_TOKEN", "change:me")
)

config(:double_gis_monitor, :dispatch,
  channel_id: System.get_env("DGM_TG_CHANNEL", "-1") |> String.to_integer()
)

# ^^ Project BOT configuration ^^

# vv Project LOGGING configuration vv
# The default configuration can be changed by setting these environment variables when starting the application:
#  DGM_LOG_DIR - path to directory to write log files
log_dir = System.get_env("DGM_LOG_DIR", nil)

if not is_nil(log_dir) and String.length(log_dir) > 0 do
  config(:logger,
    backends: [
      {LoggerFileBackend, :info_log},
      {LoggerFileBackend, :error_log},
      :console
    ]
  )

  config(:logger, :info_log,
    format: "[$date] [$time] [$level] $metadata: $message\n",
    metadata: [:registered_name, :pid, :mfa],
    level: :info,
    path: log_dir <> "/info.log"
  )

  config(:logger, :error_log,
    format: "[$date] [$time] [$level] $metadata: $message\n",
    metadata: [:registered_name, :pid, :mfa],
    level: :error,
    path: log_dir <> "/error.log"
  )
end

# ^^ Project LOGGING configuration ^^

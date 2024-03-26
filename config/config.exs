import Config

config(:logger, :console,
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa]
)

# interval should be in seconds
config(:double_gis_monitor, :poller,
  city: "novosibirsk",
  layers: ["crash", "roadwork", "restriction", "comment", "other"],
  interval: 60
)

# import_config("#{config_env()}.exs")

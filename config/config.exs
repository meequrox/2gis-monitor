import Config

config(:double_gis_monitor, DoubleGisMonitor.Repo,
  database: "double_gis_monitor_repo",
  username: "postgres",
  password: "CWPIG-QRVIY-IWDMJ-PDQMV",
  hostname: "localhost",
  port: 5432
)

config(:double_gis_monitor,
  ecto_repos: [DoubleGisMonitor.Repo]
)

# interval should be in seconds
config(:double_gis_monitor, :poller,
  city: "novosibirsk",
  layers: ["crash", "roadwork", "restriction", "comment", "other"],
  interval: 60
)

config(:logger, :console,
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa]
)

# import_config("#{config_env()}.exs")

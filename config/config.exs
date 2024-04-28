import Config

config(:logger, :console,
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa],
  colors: [info: :light_green]
)

config(:double_gis_monitor, DoubleGisMonitor.Db.Repo,
  database: "double_gis_monitor_repo",
  username: "postgres",
  password: "CWPIG-QRVIY-IWDMJ-PDQMV",
  hostname: "localhost",
  port: 5432,
  log: :info
)

config(:double_gis_monitor,
  ecto_repos: [DoubleGisMonitor.Db.Repo]
)

config(:telegex, caller_adapter: {HTTPoison, [recv_timeout: 5 * 1000]})

# TODO: document all :double_gis_monitor options
# interval should be in seconds
config(:double_gis_monitor, :fetch,
  city: "Novosibirsk",
  layers: ["crash", "roadwork", "restriction", "comment", "other"],
  interval: 600
)

config(:double_gis_monitor, :dispatch, timezone: "Asia/Krasnoyarsk")

if File.exists?("config/private.exs") do
  import_config("private.exs")
else
  raise("Private config file not found, please read the docs!")
end

if File.exists?("config/#{config_env()}.exs") do
  import_config("#{config_env()}.exs")
end

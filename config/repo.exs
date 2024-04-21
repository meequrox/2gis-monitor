import Config

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

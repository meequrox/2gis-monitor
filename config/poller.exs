import Config

# interval should be in seconds
config(:double_gis_monitor, :poller,
  city: "novosibirsk",
  layers: ["crash", "roadwork", "restriction", "comment", "other"],
  interval: 600
)

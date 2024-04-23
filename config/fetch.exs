import Config

# interval should be in seconds
config(:double_gis_monitor, :fetch,
  city: "Novosibirsk",
  layers: ["crash", "roadwork", "restriction", "comment", "other"],
  interval: 600
)

import Config

config(:logger,
  backends: [
    {LoggerFileBackend, :debug_log},
    {LoggerFileBackend, :info_log},
    {LoggerFileBackend, :error_log},
    :console
  ]
)

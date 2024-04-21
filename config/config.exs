import Config

config(:logger, :console,
  format: "[$date] [$time] [$level] $metadata: $message\n",
  metadata: [:registered_name, :pid, :mfa],
  colors: [info: :light_green]
)

config(:tesla, Tesla.Middleware.Logger, debug: false)

import_config("repo.exs")
import_config("poller.exs")
import_config("dispatcher.exs")

if File.exists?("config/private.exs") do
  import_config("private.exs")
else
  raise("Private config file not found, please read the docs!")
end

if File.exists?("config/#{config_env()}.exs") do
  import_config("#{config_env()}.exs")
end

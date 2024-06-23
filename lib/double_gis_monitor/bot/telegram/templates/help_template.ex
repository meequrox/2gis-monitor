defmodule DoubleGisMonitor.Bot.Telegram.HelpTemplate do
  def render(commands) when is_list(commands) do
    Enum.map_join(commands, "\n", fn
      %{command: cmd, description: desc} ->
        "/" <> cmd <> " - " <> desc
    end)
  end
end

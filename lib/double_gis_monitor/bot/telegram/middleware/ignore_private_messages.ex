defmodule DoubleGisMonitor.Bot.Telegram.Middleware.IgnorePrivateMessages do
  use ExGram.Middleware

  require Logger

  alias ExGram.Model

  @impl true
  def call(
        %ExGram.Cnt{
          :bot_info => %Model.User{:username => bot_username},
          :update => %Model.Update{
            :message => %Model.Message{
              :from => %Model.User{:id => user_id},
              :chat => %Model.Chat{:id => chat_id},
              :text => "/" <> cmd
            }
          }
        } = cnt,
        _opts
      )
      when user_id !== chat_id do
    case String.contains?(cmd, "@" <> bot_username) do
      true ->
        cnt

      false ->
        reject(cnt)
    end
  end

  def call(cnt, _opts) do
    reject(cnt)
  end

  defp reject(cnt) do
    add_extra(cnt, :rejected, true)
  end
end

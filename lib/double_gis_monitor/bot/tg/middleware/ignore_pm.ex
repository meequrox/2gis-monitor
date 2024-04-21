defmodule DoubleGisMonitor.Bot.Tg.Middleware.IgnorePm do
  use ExGram.Middleware

  require Logger

  alias ExGram.Model.User
  alias ExGram.Model.Update
  alias ExGram.Model.Message
  alias ExGram.Model.Chat
  alias ExGram.Cnt

  @impl true
  def call(
        %Cnt{
          :update => %Update{
            :message => %Message{
              :from => %User{:id => user_id},
              :chat => %Chat{:id => chat_id},
              :text => text
            }
          }
        } = cnt,
        _opts
      )
      when user_id !== chat_id and not is_nil(text) do
    case String.contains?(text, "@" <> cnt.bot_info.username) do
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

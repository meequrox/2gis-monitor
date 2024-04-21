defmodule DoubleGisMonitor.Database.Repo do
  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [from: 2]

  require Logger

  alias DoubleGisMonitor.Database.Event
  alias DoubleGisMonitor.Database.Chat

  #############
  ## API
  #############

  def cleanup(events, seconds_treshold) when is_list(events) and is_integer(seconds_treshold) do
    case transaction(fn -> cleanup_in_transaction(events, seconds_treshold) end) do
      {:error, reason} = err ->
        Logger.error("Transaction failed with reason #{inspect(reason)}, no events was deleted")

        err

      any ->
        any
    end
  end

  def update_events(events) when is_list(events) do
    case transaction(fn -> update_events_in_transaction(events) end) do
      {:ok, list} ->
        list

      {:error, reason} ->
        Logger.error("Transaction failed with reason #{inspect(reason)}, no events was updated")

        []
    end
  end

  def add_chat(id, title) do
    case get(Chat, id) do
      nil ->
        insert(%Chat{id: id, title: title})

      db_chat ->
        db_chat
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_change(:title, title)
        |> update()
    end
  end

  def get_chats(), do: all(Chat)

  def chat_exists?(id) do
    query = from(c in "chats", where: c.id == ^id)

    exists?(query)
  end

  def delete_chat(%{:id => id, :title => title}) do
    case delete(%Chat{id: id, title: title}, returning: false) do
      {:ok, _} ->
        :ok

      {:error, c} ->
        if in_transaction?() do
          rollback(c)
        end

        :error
    end
  end

  #############
  ## Private
  #############

  defp cleanup_in_transaction(events, seconds_treshold) do
    ts_now = DateTime.utc_now() |> DateTime.to_unix()

    query =
      from(e in "events",
        where: ^ts_now - e.timestamp > ^seconds_treshold,
        select: [:uuid]
      )

    outdated_db_events = all(query)

    reduce_fn =
      fn %{:uuid => outdated_uuid}, acc ->
        case Enum.find(events, nil, fn %{:uuid => uuid} -> uuid === outdated_uuid end) do
          nil ->
            case delete(%Event{uuid: outdated_uuid}, returning: false) do
              {:ok, s} ->
                s

              {:error, c} ->
                rollback(c)
            end

            acc + 1

          _ ->
            acc
        end
      end

    Enum.reduce(outdated_db_events, 0, reduce_fn)
  end

  def update_events_in_transaction(events) when is_list(events) do
    filter_fn = fn e -> ensure_inserted?(e) end

    Enum.filter(events, filter_fn)
  end

  defp ensure_inserted?(
         %{
           :uuid => uuid,
           :comment => comment,
           :likes => likes,
           :dislikes => dislikes,
           :attachments_count => atch_count,
           :attachments_list => atch_list
         } = e
       )
       when is_binary(uuid) do
    case get(Event, uuid) do
      nil ->
        insert(e)
        true

      %{
        :comment => db_comment,
        :likes => db_likes,
        :dislikes => db_dislikes,
        :attachments_count => db_atch_count
      } = db_event ->
        case db_comment !== comment or db_likes !== likes or db_dislikes !== dislikes or
               db_atch_count !== atch_count do
          true ->
            db_event
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_change(:comment, comment)
            |> Ecto.Changeset.put_change(:likes, likes)
            |> Ecto.Changeset.put_change(:dislikes, dislikes)
            |> Ecto.Changeset.put_change(:attachments_count, atch_count)
            |> Ecto.Changeset.put_change(:attachments_list, atch_list)
            |> update()

            true

          false ->
            false
        end
    end
  end

  defp ensure_inserted?(%{} = e) do
    Logger.warning("Event #{inspect(e)} doest not contain required keys!")
    false
  end
end

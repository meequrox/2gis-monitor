defmodule DoubleGisMonitor.Db.Utils.Event do
  require Logger

  import Ecto.Query, only: [from: 2]

  alias DoubleGisMonitor.Db

  def cleanup(events, seconds_treshold) when is_list(events) and is_integer(seconds_treshold) do
    case Db.Repo.transaction(fn -> cleanup(:transaction, events, seconds_treshold) end) do
      {:error, reason} = err ->
        Logger.error("Transaction failed with reason #{inspect(reason)}, no events was deleted")

        err

      any ->
        any
    end
  end

  def insert_or_update(events) when is_list(events) do
    case Db.Repo.transaction(fn -> insert_or_update(:transaction, events) end) do
      {:ok, result} ->
        result

      {:error, reason} ->
        Logger.error("Transaction failed with reason #{inspect(reason)}, no events was updated")

        []
    end
  end

  def reset() do
    table = Db.Event.__schema__(:source)

    Db.Repo.query("TRUNCATE #{table}", [])
  end

  defp cleanup(:transaction, events, seconds_treshold) do
    ts_now = DateTime.utc_now() |> DateTime.to_unix()

    query =
      from(e in "events",
        where: ^ts_now - e.timestamp > ^seconds_treshold,
        select: [:uuid]
      )

    outdated_db_events = Db.Repo.all(query)

    reduce_fn =
      fn %{:uuid => outdated_uuid}, acc ->
        case Enum.find(events, nil, fn %{:uuid => uuid} -> uuid === outdated_uuid end) do
          nil ->
            case Db.Repo.delete(%Db.Event{uuid: outdated_uuid}, returning: false) do
              {:ok, s} ->
                s

              {:error, c} ->
                Db.Repo.rollback(c)
            end

            acc + 1

          _ ->
            acc
        end
      end

    Enum.reduce(outdated_db_events, 0, reduce_fn)
  end

  def insert_or_update(:transaction, events) when is_list(events) do
    events_with_op = for e <- events, do: ensure_inserted?(e)

    events_with_op
    |> Enum.group_by(fn {op, _e} -> op end, fn {_op, e} -> e end)
    |> Map.delete(:skip)
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
    case Db.Repo.get(Db.Event, uuid) do
      nil ->
        case Db.Repo.insert(e) do
          {:ok, _} ->
            {:insert, e}

          {:error, c} ->
            Db.Repo.rollback(c)
        end

      db_event ->
        event_updated? =
          db_event.comment !== comment or db_event.likes !== likes or
            db_event.dislikes !== dislikes or db_event.attachments_count !== atch_count

        case event_updated? do
          true ->
            changeset =
              db_event
              |> Ecto.Changeset.change()
              |> Ecto.Changeset.put_change(:comment, comment)
              |> Ecto.Changeset.put_change(:likes, likes)
              |> Ecto.Changeset.put_change(:dislikes, dislikes)
              |> Ecto.Changeset.put_change(:attachments_count, atch_count)
              |> Ecto.Changeset.put_change(:attachments_list, atch_list)

            case Db.Repo.update(changeset) do
              {:ok, _} ->
                {:update, e}

              {:error, c} ->
                Db.Repo.rollback(c)
            end

          false ->
            {:skip, e}
        end
    end
  end

  defp ensure_inserted?(%{} = e) do
    Logger.warning("Event #{inspect(e)} doest not contain required keys!")

    {:skip, e}
  end
end

defmodule DoubleGisMonitor.Pipeline.Process do
  @moduledoc """
  A pipeline module that receives a list of event maps with binary keys, applies various transformations to them, and then inserts or updates the corresponding database records.

  Before real processing begins, the database is cleaned.
  If some event in the database was added N hours ago and is no longer displayed on the 2GIS map, it is deleted from the database.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias DoubleGisMonitor.Db, as: Database

  @spec call(list(map())) :: {:ok, %{update: list(map()), insert: list(map())}} | {:error, atom()}
  def call(events) when is_list(events), do: process(events)

  defp process(events) when is_list(events) do
    with {:ok, new_events} <- convert_events_to_db(events),
         {:ok, outdated_db_events} <- get_outdated_events(),
         {:ok, db_events_to_delete} <- find_disappeared_events(new_events, outdated_db_events),
         {:ok, deleted_events} <- delete_outdated_events(db_events_to_delete),
         {:ok, _deleted_messages} <- delete_outdated_messages(deleted_events),
         {:ok, result_map} <- insert_or_update_events(new_events),
         {:ok, fixed_result_map} <- fix_result_map(result_map) do
      %{:update => updated_events, :insert => inserted_events} = fixed_result_map

      Logger.info(
        "#{Enum.count(deleted_events)} events deleted, #{Enum.count(updated_events)} updated, #{Enum.count(inserted_events)} inserted."
      )

      {:ok, fixed_result_map}
    else
      {:error, {:delete_outdated_events, changeset}} ->
        Logger.error("Database cleanup failed while deleting events: : #{inspect(changeset)}.")
        {:error, :events_cleanup}

      {:error, {:delete_outdated_messages, changeset}} ->
        Logger.error("Database cleanup failed while deleting messages: #{inspect(changeset)}.")
        {:error, :messages_cleanup}

      {:error, {:insert_or_update_events, changeset}} ->
        Logger.error("Failed to update and insert events: #{inspect(changeset)}.")
        {:error, :insert_or_update}

      other ->
        Logger.critical("Unhandled result: #{inspect(other)}")
        {:error, :undefined}
    end
  end

  defp fix_result_map(result_map) when is_map(result_map) do
    new_map =
      result_map
      |> Map.update(:update, [], fn existing -> existing end)
      |> Map.update(:insert, [], fn existing -> existing end)

    {:ok, new_map}
  end

  defp insert_or_update_events(events) when is_list(events) do
    transaction_fun =
      fn ->
        Enum.map(events, fn event -> insert_or_update_event(event) end)
      end

    case Database.Repo.transaction(transaction_fun) do
      {:ok, events_with_operation} ->
        key_fun = fn {_event, operation} -> operation end
        value_fun = fn {event, _operation} -> event end

        events_map =
          events_with_operation
          |> Enum.group_by(key_fun, value_fun)
          |> Map.delete(:skip)

        {:ok, events_map}

      {:error, {:insert_or_update_event, changeset}} ->
        Logger.error("Failed to insert or update event: #{inspect(changeset)}. Rolled back.")
        {:error, {:insert_or_update_events, changeset}}
    end
  end

  defp insert_or_update_event(%Database.Event{:uuid => uuid} = event)
       when is_binary(uuid) do
    case Database.Repo.get(Database.Event, uuid) do
      nil ->
        insert_event(event)

      db_event ->
        case different_events?(db_event, event) do
          true ->
            update_event(db_event, event)

          false ->
            {event, :skip}
        end
    end
  end

  defp insert_event(event) when is_map(event) do
    case Database.Repo.insert(event) do
      {:ok, _struct} ->
        {event, :insert}

      {:error, changeset} ->
        Database.Repo.rollback({:insert_or_update_event, changeset})
    end
  end

  defp update_event(
         old_event,
         %Database.Event{
           :comment => new_comment,
           :feedback => new_feedback,
           :attachments => new_attachments
         } = new_event
       )
       when is_map(new_feedback) and is_map(new_attachments) do
    changeset =
      old_event
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:comment, new_comment)
      |> Ecto.Changeset.put_change(:feedback, new_feedback)
      |> Ecto.Changeset.put_change(:attachments, new_attachments)

    case Database.Repo.update(changeset) do
      {:ok, _struct} ->
        {new_event, :update}

      {:error, changeset} ->
        Database.Repo.rollback({:insert_or_update_event, changeset})
    end
  end

  defp different_events?(
         %{
           :comment => db_comment,
           :feedback => %{"likes" => db_likes, "dislikes" => db_dislikes},
           :attachments => %{"count" => db_atch_count}
         },
         new_event
       )
       when is_map(new_event) do
    db_likes != new_event.feedback.likes or
      db_dislikes != new_event.feedback.dislikes or
      db_atch_count != new_event.attachments.count or
      db_comment != new_event.comment
  end

  defp delete_outdated_messages(events) when is_list(events) do
    map_fun =
      fn %{:uuid => uuid} = event ->
        case Database.Repo.get(Database.Message, uuid) do
          nil -> {:ok, event}
          struct -> delete_outdated_event_messages(struct)
        end
      end

    transaction_fun = fn -> Enum.map(events, map_fun) end

    case Database.Repo.transaction(transaction_fun) do
      {:ok, deleted_messages} ->
        {:ok, deleted_messages}

      {:error, {:delete_outdated_event_messages, changeset}} ->
        Logger.error("Failed to delete outdated messages: #{inspect(changeset)}. Rolled back.")
        {:error, {:delete_outdated_messages, changeset}}
    end
  end

  defp delete_outdated_event_messages(%{:uuid => uuid}) when is_binary(uuid) do
    case Database.Repo.delete(%Database.Message{uuid: uuid},
           returning: false
         ) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        Database.Repo.rollback({:delete_outdated_event_messages, changeset})
    end
  end

  defp delete_outdated_events(events) when is_list(events) do
    transaction_fun =
      fn ->
        Enum.map(events, fn event -> delete_outdated_event(event) end)
      end

    case Database.Repo.transaction(transaction_fun) do
      {:ok, deleted_events} ->
        {:ok, deleted_events}

      {:error, {:delete_outdated_event, changeset}} ->
        Logger.error("Failed to delete outdated event: #{inspect(changeset)}. Rolled back.")
        {:error, {:delete_outdated_events, changeset}}
    end
  end

  defp delete_outdated_event(%{:uuid => uuid}) do
    case Database.Repo.delete(%Database.Event{uuid: uuid}, returning: false) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        Database.Repo.rollback({:delete_outdated_event, changeset})
    end
  end

  defp find_disappeared_events(new_events, db_events)
       when is_list(new_events) and is_list(db_events) do
    filter_fun =
      fn %{:uuid => db_uuid} ->
        find_fun =
          fn %Database.Event{:uuid => uuid} ->
            uuid == db_uuid
          end

        Enum.find(new_events, nil, find_fun) === nil
      end

    outdated_events = Enum.filter(db_events, filter_fun)

    {:ok, outdated_events}
  end

  defp get_outdated_events() do
    ts_now = DateTime.utc_now() |> DateTime.to_unix()
    outdate_hours = 6

    events =
      from(e in "events",
        where: ^ts_now - e.timestamp > ^(outdate_hours * 3600),
        select: [:uuid]
      )
      |> Database.Repo.all()

    {:ok, events}
  end

  defp convert_events_to_db(events) when is_list(events) do
    result =
      for event <- events do
        {:ok, converted_event} = convert_event_to_db(event)
        converted_event
      end
      |> Enum.filter(fn %Database.Event{:uuid => uuid} -> is_binary(uuid) end)

    {:ok, result}
  end

  defp convert_event_to_db(
         %{
           "id" => id,
           "timestamp" => ts,
           "type" => type,
           "user" => user_info,
           "location" => %{"coordinates" => [lon, lat]},
           "feedbacks" => %{"likes" => likes, "dislikes" => dislikes},
           "attachments" => {atch_count, atch_list}
         } = event
       )
       when is_binary(id) and is_integer(ts) and is_binary(type) and is_map(user_info) and
              is_float(lon) and is_float(lat) and is_integer(likes) and is_integer(dislikes) do
    new_event = %Database.Event{
      uuid: id,
      timestamp: ts,
      type: type,
      username: Map.get(user_info, "name"),
      coordinates: %{lat: lat, lon: lon},
      comment: Map.get(event, "comment"),
      feedback: %{likes: likes, dislikes: dislikes * -1},
      attachments: %{count: atch_count, list: atch_list}
    }

    {:ok, new_event}
  end

  defp convert_event_to_db(_other) do
    {:ok, %Database.Event{uuid: :invalid}}
  end
end

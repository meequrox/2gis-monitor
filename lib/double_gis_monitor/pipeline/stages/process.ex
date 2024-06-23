defmodule DoubleGisMonitor.Pipeline.Stage.Process do
  @moduledoc """
  A pipeline module that receives a list of event maps with binary keys,
  applies various transformations to them, and then inserts or updates the corresponding database records.

  Before real processing begins, the database is cleaned.
  If some event in the database was added N minutes ago and is no longer displayed on the 2GIS map,
  it is deleted from the database.
  """

  require Logger

  alias DoubleGisMonitor.Database

  @spec run(list(map()), map()) :: %{
          delete: list(map()),
          update: list(map()),
          insert: list(map())
        }
  def run(fetched_events, %{interval: interval}) do
    outdated_events = find_outdated_events(fetched_events, interval)
    grouped_events = group_fetched_events(fetched_events)

    result =
      grouped_events
      |> Map.drop([:skip])
      |> Map.put(:delete, outdated_events)
      |> Map.update(:update, [], fn existing -> existing end)
      |> Map.update(:insert, [], fn existing -> existing end)

    Logger.info(
      "Process: delete #{Enum.count(outdated_events)}, update #{Enum.count(result.update)}, insert #{Enum.count(result.insert)}"
    )

    result
  end

  defp find_outdated_events(fetched_events, interval) do
    interval
    |> Database.EventHandler.get_old()
    |> Enum.filter(fn %{uuid: outdated_uuid} ->
      Enum.find(fetched_events, nil, fn %{uuid: fetched_uuid} ->
        fetched_uuid == outdated_uuid
      end)
      |> is_nil()
    end)
  end

  defp group_fetched_events(events) do
    Enum.group_by(events, fn %{uuid: uuid} = event ->
      case Database.EventHandler.get_by_uuid(uuid) do
        nil ->
          :insert

        existing ->
          if different_events?(existing, event) do
            :update
          else
            :skip
          end
      end
    end)
  end

  defp different_events?(
         %{
           comment: comment,
           likes: likes,
           dislikes: dislikes,
           images_count: images_count
         },
         %{
           comment: comment,
           likes: likes,
           dislikes: dislikes,
           images_count: images_count
         }
       ) do
    false
  end

  defp different_events?(_db_event, _new_event) do
    true
  end
end

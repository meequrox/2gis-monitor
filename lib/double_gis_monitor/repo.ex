defmodule DoubleGisMonitor.Repo do
  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres

  require Logger

  #############
  ## API
  #############

  def cleanup(events, hours) do
    outdated_db_events =
      DoubleGisMonitor.Event |> DoubleGisMonitor.Repo.all() |> find_outdated_events(hours)

    reduce_fn =
      fn %{:uuid => outdated_uuid} = s, acc ->
        find_fn =
          fn %{:uuid => uuid} ->
            uuid === outdated_uuid
          end

        case Enum.find(events, nil, find_fn) do
          nil ->
            DoubleGisMonitor.Repo.delete(s, returning: false)
            acc + 1

          _ ->
            acc
        end
      end

    {:ok, Enum.reduce(outdated_db_events, 0, reduce_fn)}
  end

  @spec insert_new(any()) :: list()
  def insert_new(events) do
    filter_fn = fn e -> ensure_inserted?(e) end
    Enum.filter(events, filter_fn)
  end

  #############
  ## Private
  #############

  defp ensure_inserted?(
         %{:uuid => uuid, :likes => likes, :dislikes => dislikes, :attachments_count => attch_cnt} =
           e
       ) do
    case DoubleGisMonitor.Repo.get(DoubleGisMonitor.Event, uuid) do
      nil ->
        DoubleGisMonitor.Repo.insert(e)
        true

      db_event ->
        case db_event.likes !== likes or db_event.dislikes !== dislikes or
               db_event.attachments_count !== attch_cnt do
          true ->
            DoubleGisMonitor.Repo.update(e)
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

  defp find_outdated_events(db_events, hours) do
    current_datetime = DateTime.utc_now()

    filter_fn =
      fn %{:datetime => event_datetime} ->
        DateTime.diff(current_datetime, event_datetime, :hour) > hours
      end

    Enum.filter(db_events, filter_fn)
  end
end

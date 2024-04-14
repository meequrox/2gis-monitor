defmodule DoubleGisMonitor.Repo do
  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query, only: [from: 2]

  #############
  ## API
  #############

  def cleanup(events, hours) do
    query = from(e in "events", select: {e.uuid, e.datetime})
    outdated_db_events = find_outdated_events(DoubleGisMonitor.Repo.all(query), hours)

    f_cleanup =
      fn %{:uuid => outdated_uuid} = s, acc ->
        f_persist =
          fn %{:uuid => uuid} ->
            uuid === outdated_uuid
          end

        case Enum.find(events, nil, f_persist) do
          nil ->
            DoubleGisMonitor.Repo.delete(s, returning: false)
            acc + 1

          _ ->
            acc
        end
      end

    n = Enum.reduce(outdated_db_events, 0, f_cleanup)

    {:ok, n}
  end

  #############
  ## Private
  #############

  defp find_outdated_events(db_events, hours) do
    current_datetime = DateTime.utc_now()

    f =
      fn %{:datetime => event_datetime} ->
        DateTime.diff(current_datetime, event_datetime, :hours) > hours
      end

    Enum.filter(db_events, f)
  end
end

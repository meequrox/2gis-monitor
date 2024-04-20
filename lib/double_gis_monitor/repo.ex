defmodule DoubleGisMonitor.Repo do
  use Ecto.Repo,
    otp_app: :double_gis_monitor,
    adapter: Ecto.Adapters.Postgres

  require Logger

  #############
  ## API
  #############

  def cleanup(events, hours) when is_list(events) and is_integer(hours) do
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

  def insert_new(events) when is_list(events) do
    filter_fn = fn e -> ensure_inserted?(e) end

    Enum.filter(events, filter_fn)
  end

  #############
  ## Private
  #############

  defp ensure_inserted?(
         %{
           :uuid => uuid,
           :comment => comment,
           :likes => likes,
           :dislikes => dislikes,
           :attachments_count => atch_count,
           :attachments_list => atch_list
         } =
           e
       )
       when is_binary(uuid) do
    case DoubleGisMonitor.Repo.get(DoubleGisMonitor.Event, uuid) do
      nil ->
        DoubleGisMonitor.Repo.insert(e)
        true

      %{
        :comment => db_comment,
        :likes => db_likes,
        :dislikes => db_dislikes,
        :attachments_count => db_atch_count
      } ->
        case db_comment !== comment or db_likes !== likes or db_dislikes !== dislikes or
               db_atch_count !== atch_count do
          true ->
            e
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_change(:comment, comment)
            |> Ecto.Changeset.put_change(:likes, likes)
            |> Ecto.Changeset.put_change(:dislikes, dislikes)
            |> Ecto.Changeset.put_change(:attachments_count, atch_count)
            |> Ecto.Changeset.put_change(:attachments_list, atch_list)
            |> DoubleGisMonitor.Repo.update()

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

  defp find_outdated_events(db_events, hours) when is_list(db_events) and is_integer(hours) do
    current_datetime = DateTime.utc_now()

    filter_fn =
      fn %{:datetime => event_datetime} ->
        DateTime.diff(current_datetime, event_datetime, :hour) > hours
      end

    Enum.filter(db_events, filter_fn)
  end
end

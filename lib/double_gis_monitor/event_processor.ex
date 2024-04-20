defmodule DoubleGisMonitor.EventProcessor do
  use Agent
  require Logger

  @outdate_hours 24

  #############
  ## API
  #############

  @doc """
  Returns child specification for supervisor.
  """
  def child_spec() do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      restart: :permanent,
      type: :worker,
      shutdown: 10000
    }
  end

  def start_link([]) do
    Agent.start_link(__MODULE__, :init, [], name: __MODULE__)
  end

  def init() do
    %{first_run: true, last_cleanup: DateTime.from_unix!(0)}
  end

  def process(events) when is_list(events) do
    state = Agent.get(__MODULE__, fn map -> map end)
    datetime_now = DateTime.utc_now()

    converted_events = events |> Enum.map(fn e -> convert_event_to_db(e) end)

    new_state =
      case state.first_run or
             DateTime.diff(datetime_now, state.last_cleanup, :hour) > @outdate_hours do
        true ->
          Logger.info("Database cleanup started")

          case DoubleGisMonitor.Repo.cleanup(converted_events, @outdate_hours) do
            {:ok, n} when is_integer(n) ->
              Logger.info("Deleted #{n} old database entries")
              %{state | first_run: false, last_cleanup: datetime_now}

            err ->
              Logger.warning("Unknown result from cleanup function: #{inspect(err)}")
              state
          end

        false ->
          %{state | first_run: false}
      end

    Agent.update(__MODULE__, fn _ -> new_state end)

    new_events = DoubleGisMonitor.Repo.insert_new(converted_events)

    # Send new events to dispatcher module

    Logger.info(
      "Processed #{Enum.count(converted_events)} events, inserted (or updated) #{Enum.count(new_events)} events!"
    )
  end

  #############
  ## Private
  #############

  defp convert_event_to_db(
         %{
           "id" => id,
           "timestamp" => ts,
           "type" => type,
           "user" => user_info,
           "location" => %{"coordinates" => [lon, lat]},
           "feedbacks" => %{"likes" => likes, "dislikes" => dislikes},
           "attachments" => {atch_list, atch_count}
         } = e
       )
       when is_integer(ts) and is_map(user_info) do
    %DoubleGisMonitor.Event{
      uuid: id,
      datetime: DateTime.from_unix!(ts),
      type: type,
      username: Map.get(user_info, "name"),
      coordinates: %{:lat => lat, :lon => lon},
      comment: Map.get(e, "comment"),
      likes: likes,
      dislikes: dislikes,
      attachments_count: atch_count,
      attachments_list: atch_list
    }
  end

  defp convert_event_to_db(_) do
    %DoubleGisMonitor.Event{}
  end
end

defmodule DoubleGisMonitor.Worker.Processor do
  use Agent

  require Logger

  alias DoubleGisMonitor.Db
  alias DoubleGisMonitor.Worker.Dispatcher

  @outdate_hours 24

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
    state = Agent.get(__MODULE__, fn m -> m end)
    datetime_now = DateTime.utc_now()

    converted_events = events |> Enum.map(fn e -> convert_event_to_db(e) end)

    new_state =
      case state.first_run or
             DateTime.diff(datetime_now, state.last_cleanup, :hour) > @outdate_hours do
        true ->
          Logger.info("Database cleanup started")

          case Db.Utils.Event.cleanup(converted_events, @outdate_hours * 3600) do
            {:ok, n} when is_integer(n) ->
              Logger.info("Deleted #{n} old database entries")
              %{state | first_run: false, last_cleanup: datetime_now}

            {:error, reason} ->
              Logger.error("Database cleanup failed with reason #{inspect(reason)}")
              state
          end

        false ->
          %{state | first_run: false}
      end

    Agent.update(__MODULE__, fn _ -> new_state end)

    events =
      Db.Utils.Event.insert_or_update(converted_events)
      |> Map.update(:update, [], fn ex -> ex end)
      |> Map.update(:insert, [], fn ex -> ex end)

    Dispatcher.dispatch(events)

    updated_count = Map.get(events, :update) |> Enum.count()
    inserted_count = Map.get(events, :insert) |> Enum.count()

    Logger.info(
      "Events: processed #{Enum.count(converted_events)}, inserted #{inserted_count}, updated #{updated_count}."
    )
  end

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
    %Db.Event{
      uuid: id,
      timestamp: ts,
      type: type,
      username: Map.get(user_info, "name"),
      coordinates: %{:lat => lat, :lon => lon},
      comment: Map.get(e, "comment"),
      likes: likes,
      dislikes: dislikes * -1,
      attachments_count: atch_count,
      attachments_list: atch_list
    }
  end

  defp convert_event_to_db(_) do
    %Db.Event{}
  end
end
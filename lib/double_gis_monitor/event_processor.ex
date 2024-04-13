defmodule EventProcessor do
  use Agent
  require Logger

  import Ecto.Query, only: [from: 2]

  @outdate_hours 24

  #############
  ## API
  #############

  @doc """
  Returns child specification for supervisor.
  """
  @spec child_spec() :: %{
          :id => atom() | term(),
          :start => {module(), atom(), [term()]},
          :restart => :permanent | :transient | :temporary,
          :shutdown => timeout() | :brutal_kill,
          :type => :worker | :supervisor
        }
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
    %{first_run: true, last_cleanup: nil}
  end

  def process(events) do
    ensure_db_cleaned(events)
    # TODO(0): insert new events in db
    # TODO(1):
  end

  #############
  ## Private
  #############

  defp ensure_db_cleaned(events) do
    %{first_run: first_run, last_cleanup: last_cleanup} = Agent.get(__MODULE__, fn map -> map end)

    case first_run or DateTime.diff(DateTime.utc_now(), last_cleanup) > @outdate_hours do
      true ->
        Logger.info("Database cleanup started")

        query = from(e in "events", select: {e.uuid, e.datetime})
        outdated_db_events = find_outdated_db_events(DoubleGisMonitor.Repo.all(query))

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
        Logger.info("Deleted #{n} old database entries")

        # TODO(1): update last_cleanup in state
        {:ok, :cleaned}

      false ->
        {:ok, :skipped}
    end
  end

  defp find_outdated_db_events(db_events) do
    current_datetime = DateTime.utc_now()

    f =
      fn %{:datetime => event_datetime} ->
        DateTime.diff(current_datetime, event_datetime) > @outdate_hours
      end

    Enum.filter(db_events, f)
  end
end

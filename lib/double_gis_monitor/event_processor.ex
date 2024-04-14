defmodule EventProcessor do
  use Agent
  require Logger

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

  @spec start_link([]) :: {:error, any()} | {:ok, pid()}
  def start_link([]) do
    Agent.start_link(__MODULE__, :init, [], name: __MODULE__)
  end

  def init() do
    %{first_run: true, last_cleanup: nil}
  end

  def process(events) do
    state = Agent.get(__MODULE__, fn map -> map end)
    datetime_now = DateTime.utc_now()

    new_state =
      case state.first_run or
             DateTime.diff(datetime_now, state.last_cleanup, :hour) > @outdate_hours do
        true ->
          Logger.info("Database cleanup started")

          case DoubleGisMonitor.Repo.cleanup(events, @outdate_hours) do
            {:ok, n} ->
              Logger.info("Deleted #{n} old database entries")
              %{state | first_run: false, last_cleanup: datetime_now}

            err ->
              Logger.warning("Unknown result from cleanup function: #{err}")
              state
          end

        false ->
          %{state | first_run: false}
      end

    Agent.update(__MODULE__, fn _old_state -> new_state end)

    # TODO(0): Insert new events in DB
  end

  #############
  ## Private
  #############
end

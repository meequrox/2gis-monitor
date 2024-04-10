defmodule DoubleGisMonitor.EventPoller do
  use Agent
  require Logger

  @user_agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.160 YaBrowser/22.5.4.904 Yowser/2.5 Safari/537.36"

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
    {:ok, initial_state} = init([])
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  def wait() do
    Process.sleep(1000)
    poll()
  end

  #############
  ## Private
  #############

  defp init([]) do
    [city: city, layers: layers, interval: interval] =
      Application.get_env(:double_gis_monitor, :poller,
        city: "moscow",
        layers: ["comment"],
        interval: 1800
      )

    layers_str =
      "[\"" <>
        (Enum.filter(layers, fn x -> valid_layer?(x) end) |> Enum.uniq() |> Enum.join("\",\"")) <>
        "\"]"

    initial_state = %{city: city, layers: layers_str, interval: interval * 1000}
    Process.spawn(__MODULE__, :wait, [], [:link])

    {:ok, initial_state}
  end

  defp wait(interval) do
    Logger.info("Waiting #{interval} ms before next poll")

    Process.sleep(interval)
    poll()
  end

  defp poll() do
    %{city: city, layers: layers, interval: interval} = Agent.get(__MODULE__, fn map -> map end)
    Logger.info("Poll options: city '#{city}', layers #{layers}")

    url = "https://tugc.2gis.com/1.0/layers/user?project=#{city}&layers=#{layers}"

    case get_event_list(url) do
      {:ok, _event_list} ->
        Logger.info("Successfully received events")

      # Send event list to EventProcessor

      {:error, reason} ->
        Logger.error(
          "Couldn't get a list of events: #{reason}. Stop trying until the next timer fires"
        )
    end

    wait(interval)
  end

  defp valid_layer?(layer) do
    valid_layers = ["camera", "crash", "roadwork", "restriction", "comment", "other"]

    Enum.member?(valid_layers, layer)
  end

  defp get_event_list(url) do
    get_event_list(url, 0, {:error, :undefined})
  end

  defp get_event_list(url, attempt, _prev_result) when attempt < 3 do
    case HTTPoison.get(url, "User-Agent": @user_agent) do
      {:ok, resp} ->
        case resp.status_code do
          200 ->
            {:ok, Jason.decode!(resp.body)}

          code ->
            Logger.warning("Request failed: status code #{code}, attempt #{attempt + 1}")

            reason = {:code, code}

            get_event_list(url, attempt + 1, {:error, reason})
        end

      {:error, reason} = result ->
        Logger.warning("Request failed: reason #{reason}, attempt #{attempt + 1}")

        get_event_list(url, attempt + 1, result)
    end
  end

  defp get_event_list(_url, _attempt, prev_result) do
    prev_result
  end
end

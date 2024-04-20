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
    [city: city, layers: layers, interval: interval] =
      Application.get_env(:double_gis_monitor, :poller,
        city: "moscow",
        layers: ["comment"],
        interval: 1800
      )

    layers =
      layers |> Enum.uniq() |> Enum.filter(fn x -> valid_layer?(x) end) |> Enum.join("\",\"")

    Process.spawn(__MODULE__, :wait, [], [:link])
    %{city: city, layers: "[\"" <> layers <> "\"]", interval: interval * 1000}
  end

  def wait() do
    Process.sleep(2000)
    poll()
  end

  #############
  ## Private
  #############

  defp valid_layer?(layer) do
    valid_layers = ["camera", "crash", "roadwork", "restriction", "comment", "other"]

    Enum.member?(valid_layers, layer)
  end

  defp wait(interval) do
    Logger.info("Waiting #{interval} ms before next poll")

    Process.sleep(interval)
    poll()
  end

  defp poll() do
    %{city: city, layers: layers, interval: interval} = Agent.get(__MODULE__, fn map -> map end)

    params = %{project: city, layers: layers}
    url = HTTPoison.Base.build_request_url("https://tugc.2gis.com/1.0/layers/user", params)

    Logger.info("Poll parameters: #{inspect(params)}")

    case fetch_events(url) do
      {:ok, events} ->
        Logger.info("Successfully received events")
        events |> include_attachments() |> DoubleGisMonitor.EventProcessor.process()

      {:error, _} ->
        Logger.error("Couldn't get a list of events. Stop trying until the next timer fires")
    end

    wait(interval)
  end

  defp fetch_events(url) do
    fetch_events(url, 0, {:error, :undefined})
  end

  defp fetch_events(url, attempt, _prev_result) when attempt < 3 do
    case HTTPoison.get(url, "User-Agent": @user_agent) do
      {:ok, resp} ->
        case resp.status_code do
          200 ->
            {:ok, Jason.decode!(resp.body)}

          code ->
            Logger.warning("Request failed: status code #{code}, attempt #{attempt + 1}")

            Process.sleep(1000)
            fetch_events(url, attempt + 1, {:error, code})
        end

      {:error, reason} ->
        Logger.warning("Request failed: reason #{inspect(reason)}, attempt #{attempt + 1}")

        Process.sleep(1000)
        fetch_events(url, attempt + 1, {:error, reason})
    end
  end

  defp fetch_events(_url, _attempt, prev_result) do
    prev_result
  end

  defp include_attachments(events) do
    map_fn =
      fn e ->
        {list, count} = get_event_attachments(e)

        e |> Map.put("attachments_count", count) |> Map.put("attachments_list", list)
      end

    Enum.map(events, map_fn)
  end

  defp get_event_attachments(%{"id" => id}) do
    params = %{id: id}
    url = HTTPoison.Base.build_request_url("https://tugc.2gis.com/1.0/event/photo", params)

    case HTTPoison.get(url, "User-Agent": @user_agent) do
      {:ok, resp} ->
        case resp.status_code do
          200 ->
            reduce_fn = fn %{"url" => url}, acc -> {url, acc + 1} end
            Jason.decode!(resp.body) |> Enum.map_reduce(0, reduce_fn)

          204 ->
            {[], 0}
        end
    end
  end

  defp get_event_attachments(_) do
    {[], 0}
  end
end

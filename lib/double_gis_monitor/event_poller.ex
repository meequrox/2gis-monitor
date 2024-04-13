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
    Agent.start_link(__MODULE__, :init, [], name: __MODULE__)
  end

  def init() do
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

    Process.spawn(__MODULE__, :wait, [], [:link])
    %{city: city, layers: layers_str, interval: interval * 1000}
  end

  def wait() do
    Process.sleep(2000)
    poll()
  end

  #############
  ## Private
  #############

  defp wait(interval) do
    Logger.info("Waiting #{interval} ms before next poll")

    Process.sleep(interval)
    poll()
  end

  defp poll() do
    %{city: city, layers: layers, interval: interval} = Agent.get(__MODULE__, fn map -> map end)
    Logger.info("Poll options: city '#{city}', layers #{layers}")

    url = "https://tugc.2gis.com/1.0/layers/user?project=#{city}&layers=#{layers}"

    case fetch_events(url) do
      {:ok, events} ->
        Logger.info("Successfully received events")

        _events = include_embeds(events)
        Logger.info("Successfully included embeds in events")

      # EventProcessor.process(events)

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

            fetch_events(url, attempt + 1, {:error, code})
        end

      {:error, reason} ->
        Logger.warning("Request failed: reason #{reason}, attempt #{attempt + 1}")

        fetch_events(url, attempt + 1, {:error, reason})
    end
  end

  defp fetch_events(_url, _attempt, prev_result) do
    prev_result
  end

  defp get_event_embeds(%{:id => id} = _event) do
    url = "https://tugc.2gis.com/1.0/event/photo?id=#{id}"

    case HTTPoison.get(url, "User-Agent": @user_agent) do
      {:ok, resp} ->
        case resp.status_code do
          200 ->
            embeds = Jason.decode!(resp.body)

            {embed_list, embed_count} =
              Enum.map_reduce(embeds, 0, fn %{:url => url} = _embed, acc -> {url, acc + 1} end)

            {embed_count, embed_list}

          204 ->
            {0, []}
        end
    end
  end

  defp get_event_embeds(_) do
    {0, []}
  end

  defp include_embeds(events) do
    f =
      fn event ->
        Map.put(event, :embeds, get_event_embeds(event))
      end

    Enum.map(events, f)
  end
end

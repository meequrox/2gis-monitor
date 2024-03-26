defmodule DoubleGisMonitor.EventPoller do
  use Agent
  require Logger

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
    [city: city, layers: layers, interval: interval] =
      Application.get_env(:double_gis_monitor, :poller,
        city: "moscow",
        layers: ["comment"],
        interval: 1800
      )

    Logger.info(
      "Agent starting for layers #{inspect(layers)} in '#{city}', poll interval is #{interval}s"
    )

    layers_str =
      "[%22" <>
        (Enum.dedup(layers) |> Enum.filter(fn x -> valid_layer?(x) end) |> Enum.join("%22,%22")) <>
        "%22]"

    initial_state = %{city: city, layers: layers_str, interval: interval * 1000}

    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  def start_polling() do
    Logger.info("Polling started")
    loop()
  end

  defp valid_layer?(layer) do
    valid_layers = ["camera", "crash", "roadwork", "restriction", "comment", "other"]
    Enum.member?(valid_layers, layer)
  end

  defp loop() do
    %{city: city, layers: layers, interval: interval} = Agent.get(__MODULE__, fn map -> map end)
    poll(city, layers)
    :timer.sleep(interval)
    loop()
  end

  defp poll(city, layers) do
    url = "https://tugc.2gis.com/1.0/layers/user?project=#{city}&layers=#{layers}"

    user_agent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.160 YaBrowser/22.5.4.904 Yowser/2.5 Safari/537.36"

    case HTTPoison.get(url, "User-Agent": user_agent) do
      {:ok, resp} ->
        if resp.status_code === 200 do
          event_list = Jason.decode!(resp.body)
          Logger.info("Successfully received events from 2GIS")
        else
          Logger.info("Request to 2GIS failed: status code #{resp.status_code}")
        end

      {:error, reason} ->
        Logger.info("Request to 2GIS failed: #{reason}")
    end
  end
end

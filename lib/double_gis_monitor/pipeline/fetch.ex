defmodule DoubleGisMonitor.Pipeline.Fetch do
  @moduledoc """
  A pipeline module that receives raw data from 2GIS servers and decodes it into a list of Elixir maps (list of events).

  Each event in the list is supplemented with attachments: the number of attachments and a list of URLs.
  """

  require Logger

  alias DoubleGisMonitor.RateLimiter

  @api_uri "tugc.2gis.com"
  @max_retries 3

  @spec call() :: {:ok, list(map())} | {:error, any()}
  def call() do
    headers = build_request_headers()

    case :events |> build_request_url() |> request_events(headers) do
      {:ok, events} ->
        events_with_attachments = fetch_attachments(events, headers)

        Logger.info(
          "Fetch complete: received #{Enum.count(events_with_attachments)} events from #{@api_uri}."
        )

        {:ok, events_with_attachments}

      {:error, error} ->
        Logger.info("Fetch failed: #{inspect(error)}.")
        {:error, error}
    end
  end

  defp request_events(url, headers, attempt \\ 0)
       when is_binary(url) and is_list(headers) and is_integer(attempt) do
    with :ok <- RateLimiter.sleep_before(__MODULE__, :request),
         {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _code} <- ensure_good_response(resp),
         {:ok, events} <- Jason.decode(resp.body) do
      {:ok, events}
    else
      {:error, error} ->
        case attempt do
          @max_retries ->
            {:error, error}

          below ->
            Logger.error("Failed to fetch events list: #{inspect(error)}. Retrying...")

            RateLimiter.sleep_before(__MODULE__, :retry)
            request_events(url, headers, below + 1)
        end
    end
  end

  defp fetch_attachments(events, headers) when is_list(events) and is_list(headers) do
    map_fun = fn
      %{"id" => id} = event ->
        case :attachments |> build_request_url(event) |> request_attachments(headers) do
          {:ok, {count, list}} ->
            Map.put(event, "attachments", {count, list})

          {:error, error} ->
            Logger.error(
              "Failed to fetch attachments for #{id}: #{inspect(error)}. Event will be ignored."
            )

            nil
        end

      _ ->
        nil
    end

    Enum.map(events, map_fun) |> Enum.filter(fn event -> not is_nil(event) end)
  end

  defp request_attachments(url, headers, attempt \\ 0)
       when is_binary(url) and is_list(headers) and is_integer(attempt) do
    with :ok <- RateLimiter.sleep_before(__MODULE__, :request),
         {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _} <- ensure_good_response(resp),
         {:ok, map_list} <- Jason.decode(resp.body) do
      url_list = Enum.map(map_list, fn %{"url" => url} -> url end)

      {:ok, {Enum.count(url_list), url_list}}
    else
      {:error, {:response, 204, _}} ->
        {:ok, {0, []}}

      {:error, error} ->
        case attempt do
          @max_retries ->
            {:error, error}

          below ->
            Logger.error("Failed to request attachments: #{inspect(error)}. Retrying...")

            RateLimiter.sleep_before(__MODULE__, :retry)
            request_attachments(url, headers, below + 1)
        end
    end
  end

  defp ensure_good_response(%{:status_code => code, :request_url => url})
       when is_integer(code) and is_binary(url) do
    case code do
      200 ->
        {:ok, 200}

      other ->
        {:error, {:response, other, url}}
    end
  end

  defp build_request_headers() do
    frontend_url = "https://2gis.ru"

    ua =
      "Mozilla/5.0 (Linux; Android 13.2; Pixel 6 XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.1757.81 Mobile Safari/537.36"

    [
      {"Accept", "application/json"},
      {"Accept-Encoding", "identity"},
      {"Accept-Language", "ru,en-US;q=0.5"},
      {"Connection", "keep-alive"},
      {"DNT", "1"},
      {"Host", "#{@api_uri}"},
      {"Origin", frontend_url},
      {"Referer", frontend_url <> "/"},
      {"Sec-Fetch-Dest", "empty"},
      {"Sec-Fetch-Mode", "cors"},
      {"Sec-Fetch-Site", "cross-site"},
      {"User-Agent", ua}
    ]
  end

  defp build_request_url(:events) do
    env = Application.fetch_env!(:double_gis_monitor, :fetch)
    [city: city, layers: layers] = Keyword.take(env, [:city, :layers])

    layers_str =
      layers
      |> Enum.uniq()
      |> Enum.filter(fn x -> valid_layer?(x) end)
      |> Enum.join("\",\"")

    params = %{
      project: String.downcase(city),
      layers: "[\"" <> layers_str <> "\"]"
    }

    HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/layers/user", params)
  end

  defp build_request_url(:attachments, %{"id" => id}) when is_binary(id) do
    HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/event/photo", %{id: id})
  end

  defp valid_layer?(layer) when is_binary(layer) do
    [
      "camera",
      "comment",
      "crash",
      "other",
      "restriction",
      "roadwork"
    ]
    |> Enum.member?(layer)
  end

  defp valid_layer?(_), do: false
end

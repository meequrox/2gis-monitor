defmodule DoubleGisMonitor.Pipeline.Stage.Fetch do
  @moduledoc """
  A pipeline module that receives raw data from 2GIS servers and decodes it into a list of Elixir maps (list of events).

  Each event in the list is supplemented with attachments: the number of attachments and a list of URLs.
  """

  require Logger

  alias DoubleGisMonitor.{Database, RateLimiter}

  @api_uri "tugc.2gis.com"
  @retries_max 3

  @spec run(map()) :: {:ok, list(map())} | {:error, term()}
  def run(%{city: city, layers: layers}) do
    headers = build_request_headers()

    :events
    |> build_request_url(city, layers)
    |> request_events(headers)
    |> case do
      {:ok, events} ->
        events_with_images =
          events
          |> convert_events_maps(city)
          |> fetch_images(headers)

        Logger.info("Fetch: #{Enum.count(events_with_images)} events")
        {:ok, events_with_images}

      {:error, error} ->
        Logger.info("Fetch failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp request_events(url, headers, attempt \\ 0) when is_integer(attempt) do
    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, 200} <- ensure_good_response(resp),
         {:ok, events} <- Jason.decode(resp.body) do
      RateLimiter.sleep(:doublegis, :request)

      {:ok, events}
    else
      {:error, error} ->
        if attempt < @retries_max do
          RateLimiter.sleep(:doublegis, :retry)
          request_events(url, headers, attempt + 1)
        else
          {:error, error}
        end
    end
  end

  defp convert_events_maps(events, city) do
    events
    |> Enum.map(fn
      %{
        "id" => uuid,
        "timestamp" => ts,
        "type" => type,
        "user" => user_info,
        "location" => %{"coordinates" => [lon, lat]},
        "feedbacks" => %{"likes" => likes, "dislikes" => dislikes}
      } = event ->
        %Database.Event{
          uuid: uuid,
          timestamp: ts,
          type: type,
          username: user_info["name"],
          geo: [lat, lon],
          comment: event["comment"],
          likes: likes,
          dislikes: dislikes * -1,
          city: city
        }

      _invalid ->
        nil
    end)
    |> Enum.filter(&is_map/1)
  end

  defp fetch_images(events, headers) do
    events
    |> Enum.map(fn
      %{uuid: uuid} = event ->
        :images
        |> build_request_url(event)
        |> request_images(headers)
        |> case do
          {:ok, {count, list}} ->
            event
            |> Map.put(:images_count, count)
            |> Map.put(:images_list, list)

          {:error, error} ->
            Logger.error(
              "Failed to fetch attachments for #{uuid}: #{inspect(error)}; event ignored"
            )

            nil
        end
    end)
    |> Enum.filter(&is_map/1)
  end

  defp request_images(url, headers, attempt \\ 0) when is_integer(attempt) do
    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, 200} <- ensure_good_response(resp),
         {:ok, images} <- Jason.decode(resp.body) do
      RateLimiter.sleep(:doublegis, :request)

      urls = Enum.map(images, fn %{"url" => url} -> url end)

      {:ok, {Enum.count(urls), urls}}
    else
      {:error, {:response, 204}} ->
        RateLimiter.sleep(:doublegis, :request)
        {:ok, {0, []}}

      {:error, error} ->
        if attempt < @retries_max do
          RateLimiter.sleep(:doublegis, :retry)
          request_images(url, headers, attempt + 1)
        else
          {:error, error}
        end
    end
  end

  defp ensure_good_response(%{status_code: 200}) do
    {:ok, 200}
  end

  defp ensure_good_response(%{status_code: code}) do
    {:error, {:response, code}}
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

  defp build_request_url(:events, city, layers) do
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

  defp build_request_url(:images, %{uuid: uuid}) do
    HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/event/photo", %{id: uuid})
  end

  defp valid_layer?(layer) do
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
end

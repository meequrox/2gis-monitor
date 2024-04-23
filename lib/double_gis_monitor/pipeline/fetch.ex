defmodule DoubleGisMonitor.Pipeline.Fetch do
  require Logger

  @api_uri "tugc.2gis.com"

  def call() do
    with {:ok, url} <- build_request_url(:events),
         {:ok, headers} <- build_request_headers(),
         {:ok, events} <- request_events(url, headers) do
      ack(events)
    end

    # TODO check for errors ^
    # TODO better logging close to the error moment
  end

  defp ack(events) do
    Logger.info("Received #{Enum.count([events])} events from server")

    events
  end

  defp request_events(url, headers) do
    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _code} <- ensure_good_response(resp),
         {:ok, events} <- Jason.decode(resp.body),
         {:ok, extended_events} <- include_attachments(events) do
      {:ok, extended_events}
    else
      # TODO retry
      {:error, %HTTPoison.Error{:reason => reason}} ->
        {:error, {:request_events, {:get, reason}}}

      # TODO retry
      {:error, {:ensure_good_response, err_code, err_url}} ->
        {:error, {:request_events, {:get, err_code, err_url}}}

      {:error, %Jason.DecodeError{:token => tok, :position => pos}} ->
        {:error, {:request_events, {:decode, tok, pos}}}

      other ->
        Logger.critical("Unhandled result: #{inspect(other)}")
        {:error, {:request_events, :undefined}}
    end
  end

  defp ensure_good_response(%{:status_code => code, :request_url => url}) do
    case code do
      200 ->
        {:ok, 200}

      other ->
        {:error, {:ensure_good_response, other, url}}
    end
  end

  defp include_attachments(events) do
    result =
      for event <- events do
        with {:ok, url} <- build_request_url(:attachments, event),
             {:ok, headers} <- build_request_headers(),
             {:ok, attachments} <- request_attachments(url, headers) do
          Map.put(event, "attachments", attachments)
        end
      end

    {:ok, result}
  end

  defp request_attachments(url, headers) do
    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _code} <- ensure_good_response(resp),
         {:ok, attachments} <- Jason.decode(resp.body) do
      {:ok, attachments}
    else
      # TODO retry
      {:error, %HTTPoison.Error{:reason => _reason}} ->
        {:ok, {0, []}}

      {:error, {:ensure_good_response, 204, _url}} ->
        {:ok, {0, []}}

      # TODO retry
      {:error, {:ensure_good_response, _other, _err_url}} ->
        {:ok, {0, []}}

      {:error, any} ->
        Logger.error("Failed to request attachments: #{inspect(any)}")
        {:ok, {0, []}}

      other ->
        Logger.critical("Unhandled result: #{inspect(other)}")
        {:ok, {0, []}}
    end
  end

  defp build_request_headers() do
    frontend_url = "https://2gis.ru"

    ua =
      "Mozilla/5.0 (Linux; Android 13.2; Pixel 6 XL) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.1757.81 Mobile Safari/537.36"

    headers = [
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

    {:ok, headers}
  end

  defp build_request_url(:events) do
    case Application.get_env(:double_gis_monitor, :fetch) do
      [city: city, layers: layers] ->
        params = %{
          project: String.downcase(city),
          layers: "[\"" <> convert_layers(layers) <> "\"]"
        }

        url = HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/layers/user", params)

        {:ok, url}

      nil ->
        {:error, {:build_request_url, :missing_fetch_config}}
    end
  end

  defp build_request_url(:attachments, %{"id" => id}) do
    params = %{id: id}
    url = HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/event/photo", params)

    {:ok, url}
  end

  defp convert_layers(layers) do
    layers
    |> Enum.uniq()
    |> Enum.filter(fn x -> valid_layer?(x) end)
    |> Enum.join("\",\"")
  end

  defp valid_layer?(layer) when is_binary(layer) do
    valid_layers = ["camera", "comment", "crash", "other", "restriction", "roadwork"]

    Enum.member?(valid_layers, layer)
  end
end

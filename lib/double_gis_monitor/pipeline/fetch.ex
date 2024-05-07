defmodule DoubleGisMonitor.Pipeline.Fetch do
  @moduledoc """
  A pipeline module that receives raw data from 2GIS servers and decodes it into a list of Elixir maps (list of events).

  Each event in the list is supplemented with attachments: the number of attachments and a list of URLs.
  """

  require Logger

  @api_uri "tugc.2gis.com"
  @request_delay 100
  @retry_delay 1500

  @spec call() :: {:ok, list(map())} | {:error, atom()}
  def call() do
    case fetch_events() do
      {:ok, events} ->
        fetch_attachments(events)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_events() do
    with {:ok, url} <- build_request_url(:events),
         {:ok, headers} <- build_request_headers(),
         {:ok, events} <- request_events(url, headers) do
      Logger.info("Received #{Enum.count(events)} events from server.")
      {:ok, events}
    else
      {:error, {:build_request_url, :missing_fetch_config}} ->
        Logger.error("There is no configuration for fetching. See config/config.exs file.")
        {:error, :config}

      {:error, {:request_events, {:get, reason}}} ->
        Logger.error("GET request failed: #{inspect(reason)}.")
        {:error, :request}

      {:error, {:request_events, {:get, err_code, err_url}}} ->
        Logger.error("Received #{err_code} response from #{err_url}.")
        {:error, :response}

      {:error, {:request_events, {:decode, tok, pos}}} ->
        Logger.error("Received invalid JSON: token #{inspect(tok)} at position #{pos}.")
        {:error, :decode}

      other ->
        Logger.critical("Unhandled result: #{inspect(other)}")
        {:error, :undefined}
    end
  end

  defp request_events(url, headers) when is_binary(url) and is_list(headers) do
    request_events(url, headers, 0)
  end

  defp request_events(url, headers, attempt)
       when is_binary(url) and is_list(headers) and is_integer(attempt) do
    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _code} <- ensure_good_response(resp),
         {:ok, events} <- Jason.decode(resp.body) do
      {:ok, events}
    else
      {:error, %HTTPoison.Error{:reason => reason}} ->
        case attempt do
          3 ->
            {:error, {:request_events, {:get, reason}}}

          below ->
            Logger.warning("GET request to #{url} failed. Retrying...")
            Process.sleep(@retry_delay)

            request_events(url, headers, below + 1)
        end

      {:error, {:ensure_good_response, err_code, err_url}} ->
        case attempt do
          3 ->
            {:error, {:request_events, {:get, err_code, err_url}}}

          below ->
            Logger.warning("Received invalid #{err_code} response from #{err_url}. Retrying...")
            Process.sleep(@retry_delay)

            request_events(url, headers, below + 1)
        end

      {:error, %Jason.DecodeError{:token => tok, :position => pos}} ->
        {:error, {:request_events, {:decode, tok, pos}}}

      other ->
        other
    end
  end

  defp fetch_attachments(events) when is_list(events) do
    result =
      for event <- events do
        with {:ok, url} <- build_request_url(:attachments, event),
             {:ok, headers} <- build_request_headers(),
             {:ok, {count, list}} <- request_attachments(url, headers) do
          Map.put(event, "attachments", {count, list})
        end
      end

    {:ok, result}
  end

  defp request_attachments(url, headers) when is_binary(url) and is_list(headers) do
    request_attachments(url, headers, 0)
  end

  defp request_attachments(url, headers, attempt)
       when is_binary(url) and is_list(headers) and is_integer(attempt) do
    Process.sleep(@request_delay)

    with {:ok, resp} <- HTTPoison.get(url, headers),
         {:ok, _code} <- ensure_good_response(resp),
         {:ok, map_list} <- Jason.decode(resp.body) do
      url_list = Enum.map(map_list, fn %{"url" => url} -> url end)

      {:ok, {Enum.count(url_list), url_list}}
    else
      {:error, %HTTPoison.Error{:reason => _reason}} ->
        case attempt do
          3 ->
            {:ok, {0, []}}

          below ->
            Logger.warning("GET request to #{url} failed. Retrying...")
            Process.sleep(@retry_delay)

            request_attachments(url, headers, below + 1)
        end

      {:error, {:ensure_good_response, 204, _url}} ->
        # There is no attachments for this event
        {:ok, {0, []}}

      {:error, {:ensure_good_response, err_code, err_url}} ->
        case attempt do
          3 ->
            {:ok, {0, []}}

          below ->
            Logger.warning("Received invalid #{err_code} response from #{err_url}. Retrying...")
            Process.sleep(@retry_delay)

            request_attachments(url, headers, below + 1)
        end

      {:error, any} ->
        Logger.error("Failed to request attachments: #{inspect(any)}.")
        {:ok, {0, []}}
    end
  end

  defp ensure_good_response(%{:status_code => code, :request_url => url})
       when is_integer(code) and is_binary(url) do
    case code do
      200 ->
        {:ok, 200}

      other ->
        {:error, {:ensure_good_response, other, url}}
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
    env = Application.get_env(:double_gis_monitor, :fetch, [])

    case Keyword.take(env, [:city, :layers]) do
      [city: city, layers: layers] ->
        params = %{
          project: String.downcase(city),
          layers: "[\"" <> convert_layers(layers) <> "\"]"
        }

        url = HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/layers/user", params)

        {:ok, url}

      _other ->
        {:error, {:build_request_url, :missing_fetch_config}}
    end
  end

  defp build_request_url(:attachments, %{"id" => id}) when is_binary(id) do
    params = %{id: id}
    url = HTTPoison.Base.build_request_url("https://#{@api_uri}/1.0/event/photo", params)

    {:ok, url}
  end

  defp convert_layers(layers) when is_list(layers) do
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

defmodule Dashboard.RSS.FetchWorker do
  @moduledoc """
  Responsible for fetching feed sources via HTTP with proper revalidation.

  Uses conditional requests (ETag, Last-Modified) and returns rich result
  tuples that the IngestService can use for scheduling decisions.

  ## Return types

  - `{:ok, feed, response}` — 200 OK, content available for processing
  - `{:not_modified, feed, response}` — 304 Not Modified
  - `{:redirect, feed, new_url, response}` — 301/308 permanent redirect
  - `{:rate_limited, feed, response}` — 429 Too Many Requests
  - `{:server_error, feed, status, response}` — 5xx server errors
  - `{:gone, feed, response}` — 410 Gone
  - `{:not_found, feed, response}` — 404 Not Found
  - `{:error, feed, reason}` — network/TLS/DNS failure
  """

  alias Dashboard.RSS.Feed
  alias Dashboard.HttpUtils

  @user_agent "Dashboard/1.0 (RSS feed bot)"

  def fetch_feed(%Feed{} = feed) do
    url = feed.canonical_url || feed.url

    headers =
      [
        {"User-Agent", @user_agent},
        {"Accept-Encoding", "gzip, deflate"}
      ]
      |> add_header("If-Modified-Since", feed.last_modified)
      |> add_header("If-None-Match", feed.etag)

    case HTTPoison.get(url, headers, recv_timeout: 15_000, timeout: 15_000) do
      {:ok, %HTTPoison.Response{} = response} ->
        classify_response(feed, response)

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, feed, reason}
    end
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: 200} = response) do
    body = maybe_decompress(response)
    response = %{response | body: body}

    case check_is_modified(response, feed) do
      :modified -> {:ok, feed, response}
      :not_modified -> {:not_modified, feed, response}
    end
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: 304} = response) do
    {:not_modified, feed, response}
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: status} = response)
       when status in [301, 308] do
    new_url = HttpUtils.extract_header("location", response)

    if new_url do
      {:redirect, feed, new_url, response}
    else
      # Redirect without Location header, treat as error
      {:error, feed, :redirect_without_location}
    end
  end

  # Temporary redirects — follow them but don't update canonical
  defp classify_response(feed, %HTTPoison.Response{status_code: status} = response)
       when status in [302, 307] do
    new_url = HttpUtils.extract_header("location", response)

    if new_url do
      # Re-fetch at the temporary URL
      temp_feed = %{feed | canonical_url: new_url}
      fetch_feed(temp_feed)
    else
      {:error, feed, :redirect_without_location}
    end
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: 429} = response) do
    {:rate_limited, feed, response}
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: 410} = response) do
    {:gone, feed, response}
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: 404} = response) do
    {:not_found, feed, response}
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: status} = response)
       when status >= 500 do
    {:server_error, feed, status, response}
  end

  defp classify_response(feed, %HTTPoison.Response{status_code: status} = _response) do
    {:error, feed, {:unexpected_status, status}}
  end

  defp check_is_modified(%HTTPoison.Response{} = response, %Feed{} = feed) do
    response_etag = HttpUtils.extract_header("etag", response)
    response_last_modified = HttpUtils.extract_header("last-modified", response)

    cond do
      HttpUtils.matching_headers?(response_etag, feed.etag) ->
        :not_modified

      HttpUtils.matching_headers?(response_last_modified, feed.last_modified) ->
        :not_modified

      true ->
        :modified
    end
  end

  defp maybe_decompress(%HTTPoison.Response{} = response) do
    content_encoding =
      HttpUtils.extract_header("content-encoding", response)

    case content_encoding do
      "gzip" -> :zlib.gunzip(response.body)
      "deflate" -> :zlib.uncompress(response.body)
      _ -> response.body
    end
  end

  defp add_header(headers, _name, nil), do: headers
  defp add_header(headers, name, value), do: [{name, value} | headers]
end

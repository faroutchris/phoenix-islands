defmodule Dashboard.RSS.FetchWorker do
  @moduledoc """
  A module responsible for fetching and verifying updates for feed sources.

  This module performs the following tasks:

  - Takes a feed source struct (`%Feed{}`).
  - Makes an HTTP GET request with cache headers if they exist.

  ## Responses:

  - **200 OK**:
    - Checks if the response headers match the cached headers to verify if the feed has been updated.
    - Returns `{:ok, feed, response}` if the feed has been updated.
    - Returns `{:not_modified, feed}` if the feed has not been updated.
  - **304 Not Modified**:
    - Returns `{:not_modified, feed}` indicating the feed has not changed.
  - **Error**:
    - Returns `{:error, reason}` indicating an error occurred during the request.

  ## Example:
      iex> Dashboard.RSS.FetchWorker.fetch_feed(feed)
      {:ok, feed, %HTTPoison.Response{...}}
  """

  alias Dashboard.RSS.Feed
  alias Dashboard.HttpUtils

  def fetch_feed(%Feed{} = feed) do
    IO.inspect(feed.url)

    headers =
      %{}
      |> HttpUtils.make_headers("If-Modified-Since", feed.last_modified)
      |> HttpUtils.make_headers("If-None-Match", feed.etag)

    with {:ok, response} <- HTTPoison.get(feed.url, headers, follow_redirect: true),
         :modified <- check_is_modified(response, feed) do
      {:ok, feed, response}
    else
      :not_modified -> {:not_modified, feed}
      {:error, error} -> {:error, error}
    end
  end

  defp check_is_modified(%HTTPoison.Response{} = response, %Feed{} = feed) do
    response_etag = HttpUtils.extract_header("etag", response)
    response_last_modified = HttpUtils.extract_header("last-modified", response)

    cond do
      response.status_code == 304 ->
        :not_modified

      HttpUtils.matching_headers?(response_last_modified, feed.last_modified) ->
        :not_modified

      HttpUtils.matching_headers?(response_etag, feed.etag) ->
        :not_modified

      true ->
        :modified
    end
  end
end

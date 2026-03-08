defmodule Dashboard.RSS.IngestService do
  @moduledoc """
  Orchestrates the feed ingestion pipeline.

  For each feed due for update, the pipeline:
  1. Fetches the feed via `FetchWorker` (HTTP with conditional requests)
  2. Compares a SHA-256 content hash to detect actual changes
  3. Parses the feed only when content has changed
  4. Delegates scheduling to the `Backoff` module
  5. Persists updated feed state via `polling_changeset`

  Handles all HTTP outcomes: 200, 304, 301/308 redirects, 429, 5xx, 404, 410.
  """

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FetchWorker
  alias Dashboard.RSS.Backoff
  alias Dashboard.HttpUtils

  def update_feeds do
    RSS.list_feed(:due_for_update)
    |> Task.async_stream(&update_pipeline/1, max_concurrency: 10, timeout: 60_000)
    |> Enum.to_list()
  end

  def update_pipeline(%Feed{} = feed) do
    case get_feed(feed) do
      {:ok, feed, response} ->
        handle_success(feed, response)

      {:not_modified, feed, response} ->
        handle_not_modified(feed, response)

      {:redirect, feed, new_url, response} ->
        handle_redirect(feed, new_url, response)

      {:rate_limited, feed, response} ->
        handle_error(feed, response, :rate_limited)

      {:server_error, feed, status, response} ->
        handle_error(feed, response, {:server_error, status})

      {:gone, feed, response} ->
        handle_gone(feed, response)

      {:not_found, feed, response} ->
        handle_error(feed, response, :not_found)

      {:error, feed, reason} ->
        handle_error(feed, nil, {:network, reason})
    end
  end

  # --- Pipeline handlers ---

  defp handle_success(%Feed{} = feed, %HTTPoison.Response{} = response) do
    case detect_changes(feed, response) do
      {:not_modified, new_hash} ->
        # Body hash unchanged — skip parsing, treat as not_modified
        next_fetch = Backoff.calculate_next(feed, response, :not_modified)
        health_status = Backoff.evaluate_health(feed)

        :telemetry.execute(
          [:dashboard, :rss, :fetch],
          %{duration: 0},
          %{feed_id: feed.id, status: :not_modified, http_status: response.status_code}
        )

        emit_status_change_if_needed(feed, health_status)

        save_polling_update(feed, %{
          content_hash: new_hash,
          last_http_status: response.status_code,
          last_fetched_at: DateTime.utc_now(),
          miss_count: (feed.miss_count || 0) + 1,
          error_count: 0,
          next_fetch: next_fetch,
          status: health_status
        })

      {:modified, new_hash} ->
        # Content changed — parse feed and update everything
        case parse_feed(response) do
          {:ok, %{feed: parsed_feed} = parsed} ->
            entries = Map.get(parsed, :entries, [])
            observed_interval = estimate_cadence(entries) || feed.observed_interval
            ttl = extract_ttl(parsed_feed)

            updated_feed = %{feed | observed_interval: observed_interval, ttl: ttl}
            next_fetch = Backoff.calculate_next(updated_feed, response, :modified)

            :telemetry.execute(
              [:dashboard, :rss, :fetch],
              %{duration: 0},
              %{feed_id: feed.id, status: :modified, http_status: response.status_code}
            )

            emit_status_change_if_needed(feed, :active)

            feed
            |> Feed.changeset(%{
              title: Map.get(parsed_feed, :title) || feed.title,
              description: Map.get(parsed_feed, :description) || feed.description,
              author: Map.get(parsed_feed, :author) || Map.get(parsed_feed, :itunes_author),
              link: Map.get(parsed_feed, :link),
              last_modified: HttpUtils.extract_header("last-modified", response),
              etag: HttpUtils.extract_header("etag", response),
              next_fetch: next_fetch,
              content_hash: new_hash,
              last_http_status: response.status_code,
              last_fetched_at: DateTime.utc_now(),
              last_new_item_at: DateTime.utc_now(),
              miss_count: 0,
              error_count: 0,
              observed_interval: observed_interval,
              ttl: ttl,
              status: :active
            })
            |> RSS.upsert_feed()

          {:error, _reason} ->
            # Parse failure — treat as error
            handle_error(feed, response, :parse_failure)
        end
    end
  end

  defp handle_not_modified(%Feed{} = feed, %HTTPoison.Response{} = response) do
    next_fetch = Backoff.calculate_next(feed, response, :not_modified)
    health_status = Backoff.evaluate_health(feed)

    :telemetry.execute(
      [:dashboard, :rss, :fetch],
      %{duration: 0},
      %{feed_id: feed.id, status: :not_modified, http_status: response.status_code}
    )

    emit_status_change_if_needed(feed, health_status)

    save_polling_update(feed, %{
      last_http_status: 304,
      last_fetched_at: DateTime.utc_now(),
      miss_count: (feed.miss_count || 0) + 1,
      error_count: 0,
      next_fetch: next_fetch,
      last_modified: HttpUtils.extract_header("last-modified", response) || feed.last_modified,
      etag: HttpUtils.extract_header("etag", response) || feed.etag,
      status: health_status
    })
  end

  defp handle_redirect(%Feed{} = feed, new_url, %HTTPoison.Response{} = response) do
    # Update canonical URL and schedule immediate re-fetch
    save_polling_update(feed, %{
      canonical_url: new_url,
      last_http_status: response.status_code,
      last_fetched_at: DateTime.utc_now(),
      next_fetch: NaiveDateTime.utc_now()
    })
  end

  defp handle_gone(%Feed{} = feed, %HTTPoison.Response{} = response) do
    next_fetch = Backoff.calculate_next(feed, response, {:error, :gone})

    :telemetry.execute(
      [:dashboard, :rss, :fetch],
      %{duration: 0},
      %{feed_id: feed.id, status: :error, reason: :gone, http_status: 410}
    )

    emit_status_change_if_needed(feed, :suspended)

    save_polling_update(feed, %{
      status: :suspended,
      suspension_reason: "410 Gone",
      last_http_status: 410,
      last_fetched_at: DateTime.utc_now(),
      error_count: (feed.error_count || 0) + 1,
      next_fetch: next_fetch
    })
  end

  defp handle_error(%Feed{} = feed, response, reason) do
    error_count = (feed.error_count || 0) + 1
    updated_feed = %{feed | error_count: error_count}

    http_status =
      case response do
        %HTTPoison.Response{status_code: code} -> code
        _ -> feed.last_http_status
      end

    next_fetch = Backoff.calculate_next(updated_feed, response, {:error, reason})
    new_status = Backoff.evaluate_health(updated_feed)

    :telemetry.execute(
      [:dashboard, :rss, :fetch],
      %{duration: 0},
      %{feed_id: feed.id, status: :error, reason: reason, http_status: http_status}
    )

    emit_status_change_if_needed(feed, new_status)

    suspension_reason =
      if new_status == :suspended do
        error_reason_string(reason)
      else
        feed.suspension_reason
      end

    save_polling_update(feed, %{
      last_http_status: http_status,
      last_fetched_at: DateTime.utc_now(),
      error_count: error_count,
      next_fetch: next_fetch,
      status: new_status,
      suspension_reason: suspension_reason
    })
  end

  # --- Change detection ---

  defp detect_changes(%Feed{} = feed, %HTTPoison.Response{} = response) do
    new_hash =
      :crypto.hash(:sha256, response.body)
      |> Base.encode16(case: :lower)

    if new_hash == feed.content_hash do
      {:not_modified, new_hash}
    else
      {:modified, new_hash}
    end
  end

  # --- Cadence estimation ---

  defp estimate_cadence(entries) when is_list(entries) do
    intervals =
      entries
      |> Enum.map(&extract_pub_date/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort(fn a, b -> DateTime.compare(a, b) == :gt end)
      |> Enum.take(10)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> DateTime.diff(a, b) end)
      |> Enum.reject(&(&1 <= 0))
      |> Enum.sort()

    case intervals do
      [] ->
        nil

      list ->
        mid = div(length(list), 2)

        if rem(length(list), 2) == 1 do
          Enum.at(list, mid)
        else
          div(Enum.at(list, mid - 1) + Enum.at(list, mid), 2)
        end
    end
  end

  defp extract_pub_date(entry) do
    raw = Map.get(entry, :pub_date) || Map.get(entry, :updated) || Map.get(entry, :published)

    case raw do
      nil ->
        nil

      date_string when is_binary(date_string) ->
        case DateTime.from_iso8601(date_string) do
          {:ok, dt, _offset} -> dt
          _ -> parse_rfc2822(date_string)
        end

      _ ->
        nil
    end
  end

  defp parse_rfc2822(date_string) do
    formats = [
      "{RFC1123}",
      "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}"
    ]

    Enum.find_value(formats, fn format ->
      case Timex.parse(date_string, format) do
        {:ok, dt} -> DateTime.from_naive!(Timex.to_naive_datetime(dt), "Etc/UTC")
        _ -> nil
      end
    end)
  rescue
    _ -> nil
  end

  # --- Feed metadata extraction ---

  defp extract_ttl(parsed_feed) do
    case Map.get(parsed_feed, :ttl) do
      nil -> nil
      ttl when is_binary(ttl) -> String.to_integer(ttl)
      ttl when is_integer(ttl) -> ttl
    end
  rescue
    _ -> nil
  end

  # --- Persistence and Telemetry ---

  defp emit_status_change_if_needed(%Feed{status: old_status}, new_status)
       when old_status != new_status do
    :telemetry.execute(
      [:dashboard, :rss, :status_change],
      %{count: 1},
      %{from: old_status, to: new_status}
    )
  end

  defp emit_status_change_if_needed(_, _), do: :ok

  defp save_polling_update(%Feed{} = feed, attrs) do
    feed
    |> Feed.polling_changeset(attrs)
    |> RSS.upsert_feed()
  end

  defp get_feed(%Feed{} = feed) do
    FetchWorker.fetch_feed(feed)
  end

  defp parse_feed(%HTTPoison.Response{} = response) do
    Gluttony.parse_string(response.body)
  end

  defp error_reason_string(:rate_limited), do: "Rate limited (429)"
  defp error_reason_string(:not_found), do: "Not found (404) for extended period"
  defp error_reason_string(:parse_failure), do: "Repeated parse failures"
  defp error_reason_string({:server_error, status}), do: "Server error (#{status})"
  defp error_reason_string({:network, reason}), do: "Network error: #{inspect(reason)}"
  defp error_reason_string(other), do: "Error: #{inspect(other)}"
end

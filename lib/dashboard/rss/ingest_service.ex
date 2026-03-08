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
            normalized_entries = normalize_entries_for_persistence(entries)

            updated_feed = %{feed | observed_interval: observed_interval, ttl: ttl}
            next_fetch = Backoff.calculate_next(updated_feed, response, :modified)

            :telemetry.execute(
              [:dashboard, :rss, :fetch],
              %{duration: 0},
              %{feed_id: feed.id, status: :modified, http_status: response.status_code}
            )

            emit_status_change_if_needed(feed, :active)

            feed_attrs = %{
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
            }

            RSS.upsert_feed_with_entries(feed, feed_attrs, normalized_entries)

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
    next_fetch = Backoff.calculate_redirect_next(feed, response)

    # Update canonical URL and schedule immediate re-fetch
    save_polling_update(feed, %{
      canonical_url: new_url,
      last_http_status: response.status_code,
      last_fetched_at: DateTime.utc_now(),
      next_fetch: next_fetch
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
    normalized_error = normalize_error(reason, response)
    error_count = (feed.error_count || 0) + 1
    updated_feed = %{feed | error_count: error_count}

    http_status =
      case response do
        %HTTPoison.Response{status_code: code} -> code
        _ -> feed.last_http_status
      end

    next_fetch = Backoff.calculate_next(updated_feed, response, {:error, normalized_error})
    new_status = Backoff.evaluate_health(updated_feed)

    :telemetry.execute(
      [:dashboard, :rss, :fetch],
      %{duration: 0},
      %{
        feed_id: feed.id,
        status: :error,
        error_class: normalized_error.class,
        reason: normalized_error.reason,
        http_status: http_status
      }
    )

    emit_status_change_if_needed(feed, new_status)

    suspension_reason =
      if new_status == :suspended do
        error_reason_string(normalized_error)
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

      %DateTime{} = dt ->
        to_utc_datetime(dt)

      %NaiveDateTime{} = ndt ->
        to_utc_datetime(ndt)

      unix when is_integer(unix) and unix > 0 ->
        to_utc_datetime(unix)

      date_string when is_binary(date_string) ->
        parse_date_string(date_string)

      _ ->
        nil
    end
  end

  defp normalize_entries_for_persistence(entries) when is_list(entries) do
    Enum.map(entries, &normalize_entry_for_persistence/1)
  end

  defp normalize_entries_for_persistence(_), do: []

  defp normalize_entry_for_persistence(entry) when is_map(entry) do
    %{
      guid: Map.get(entry, :guid) || Map.get(entry, :id),
      link: Map.get(entry, :link) || Map.get(entry, :url),
      title: Map.get(entry, :title),
      author: Map.get(entry, :author) || Map.get(entry, :dc_creator),
      summary: Map.get(entry, :summary) || Map.get(entry, :description),
      content: Map.get(entry, :content),
      published_at: extract_pub_date(entry),
      updated_at_feed: parse_entry_date(Map.get(entry, :updated)),
      enclosures: normalize_enclosures_for_persistence(extract_enclosures_for_persistence(entry))
    }
  end

  defp normalize_entry_for_persistence(_), do: %{}

  defp extract_enclosures_for_persistence(entry) when is_map(entry) do
    Map.get(entry, :enclosures) || Map.get(entry, :enclosure) || []
  end

  defp extract_enclosures_for_persistence(_), do: []

  defp normalize_enclosures_for_persistence(enclosures) when is_list(enclosures), do: enclosures
  defp normalize_enclosures_for_persistence(enclosure) when is_map(enclosure), do: [enclosure]
  defp normalize_enclosures_for_persistence(_), do: []

  defp parse_date_string(date_string) do
    date_string = String.trim(date_string)

    if date_string == "" do
      nil
    else
      parse_iso8601(date_string) || parse_rfc2822(date_string)
    end
  end

  defp parse_entry_date(nil), do: nil
  defp parse_entry_date(%DateTime{} = dt), do: to_utc_datetime(dt)
  defp parse_entry_date(%NaiveDateTime{} = ndt), do: to_utc_datetime(ndt)
  defp parse_entry_date(unix) when is_integer(unix) and unix > 0, do: to_utc_datetime(unix)

  defp parse_entry_date(value) when is_binary(value) do
    parse_date_string(value)
  end

  defp parse_entry_date(_), do: nil

  defp parse_iso8601(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _offset} ->
        dt

      _ ->
        normalized = normalize_iso8601_offset(date_string)

        if normalized == date_string do
          nil
        else
          case DateTime.from_iso8601(normalized) do
            {:ok, dt, _offset} -> dt
            _ -> nil
          end
        end
    end
  end

  defp normalize_iso8601_offset(date_string) do
    Regex.replace(~r/([+-]\d{2})(\d{2})$/, date_string, "\\1:\\2")
  end

  defp parse_rfc2822(date_string) do
    formats = [
      "{RFC1123}",
      "{RFC822}",
      "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}",
      "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m} {Z}",
      "{D} {Mshort} {YYYY} {h24}:{m}:{s} {Z}",
      "{D} {Mshort} {YYYY} {h24}:{m} {Z}"
    ]

    Enum.find_value(formats, fn format ->
      case Timex.parse(date_string, format) do
        {:ok, dt} -> to_utc_datetime(dt)
        _ -> nil
      end
    end)
  rescue
    _ -> nil
  end

  defp to_utc_datetime(%DateTime{} = dt) do
    case DateTime.shift_zone(dt, "Etc/UTC") do
      {:ok, utc_dt} -> utc_dt
      _ -> nil
    end
  end

  defp to_utc_datetime(%NaiveDateTime{} = ndt) do
    case DateTime.from_naive(ndt, "Etc/UTC") do
      {:ok, utc_dt} -> utc_dt
      _ -> nil
    end
  end

  defp to_utc_datetime(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} -> dt
      _ -> nil
    end
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
    fetch_worker().fetch_feed(feed)
  end

  defp parse_feed(%HTTPoison.Response{} = response) do
    feed_parser().parse_string(response.body)
  end

  defp error_reason_string(error) do
    case error do
      %{class: :http, code: 429} ->
        "Rate limited (429)"

      %{class: :http, code: 404} ->
        "Not found (404) for extended period"

      %{class: :parse, reason: :parse_failure} ->
        "Repeated parse failures"

      %{class: :http, code: status} ->
        "Server error (#{status})"

      %{class: :network, reason: reason} ->
        "Network error: #{inspect(reason)}"

      %{reason: reason} ->
        "Error: #{inspect(reason)}"

      other ->
        "Error: #{inspect(other)}"
    end
  end

  defp normalize_error(reason, response) do
    case {reason, response} do
      {%{class: _, reason: _} = normalized, _} ->
        normalized

      {:rate_limited, _} ->
        %{class: :http, code: 429, reason: :rate_limited}

      {:not_found, _} ->
        %{class: :http, code: 404, reason: :not_found}

      {:parse_failure, _} ->
        %{class: :parse, code: nil, reason: :parse_failure}

      {{:network, network_reason}, _} ->
        %{class: :network, code: nil, reason: network_reason}

      {{:server_error, status}, _} ->
        %{class: :http, code: status, reason: :server_error}

      {other_reason, %HTTPoison.Response{status_code: status}} ->
        %{class: :http, code: status, reason: other_reason}

      {other_reason, _} ->
        %{class: :unknown, code: nil, reason: other_reason}
    end
  end

  defp fetch_worker do
    Application.get_env(:dashboard, :rss_fetch_worker, FetchWorker)
  end

  defp feed_parser do
    Application.get_env(:dashboard, :rss_feed_parser, Gluttony)
  end
end

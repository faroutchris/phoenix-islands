defmodule Dashboard.RSS.Backoff do
  @moduledoc """
  Pure-function module for adaptive feed polling interval calculation.

  Implements a three-layer scheduling strategy:
  1. HTTP revalidation signals (Retry-After, Cache-Control max-age)
  2. Adaptive interval based on observed publication cadence
  3. Health/suspension management with exponential backoff

  ## Signal Priority Order

  1. `Retry-After` on 429/503 → hard override
  2. `Cache-Control: max-age` → server floor
  3. RSS `<ttl>` → advisory floor (only if > max-age)
  4. Observed cadence → `observed_interval / 2`, clamped
  5. No-change backoff → `current_interval × multiplier`, clamped
  6. Error backoff → exponential with jitter, clamped
  7. Default → 60 min
  """

  alias Dashboard.HttpUtils
  alias Dashboard.RSS.Feed

  # Default configuration — can be overridden via Application config
  @default_interval 60 * 60
  @min_interval 5 * 60
  @max_interval 24 * 60 * 60
  @no_change_multiplier 1.5
  @error_base_interval 15 * 60
  @error_max_interval 7 * 24 * 60 * 60
  @jitter_percent 10

  # Dormant/suspended ceilings
  @dormant_ceiling 30 * 24 * 60 * 60
  @dormant_floor 3 * 24 * 60 * 60

  # Reprobe intervals
  @reprobe_intervals [
    7 * 24 * 60 * 60,
    30 * 24 * 60 * 60,
    90 * 24 * 60 * 60
  ]

  # Health transition thresholds
  @dormant_min_days 30
  @dormant_cadence_multiplier 10
  @suspension_error_threshold 10
  @suspension_404_days 7

  @doc """
  Calculates the next fetch time based on feed state, HTTP response, and outcome.

  Returns a `NaiveDateTime` representing when the feed should next be fetched.

  ## Outcomes

  - `:modified` — new content was found
  - `:not_modified` — feed unchanged (304 or same content hash)
  - `{:error, reason}` — fetch failed
  """
  def calculate_next(%Feed{} = feed, response, outcome) do
    interval = compute_interval(feed, response, outcome)
    interval_with_jitter = apply_jitter(interval)

    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(interval_with_jitter, :second)
  end

  @doc """
  Evaluates whether a feed should transition between health states.

  Returns `:active`, `:dormant`, or `:suspended`.
  """
  def evaluate_health(%Feed{} = feed) do
    cond do
      should_suspend?(feed) -> :suspended
      should_go_dormant?(feed) -> :dormant
      true -> :active
    end
  end

  # --- Interval computation ---

  defp compute_interval(feed, response, :modified) do
    server_min = server_minimum(response)
    ttl_min = ttl_minimum(feed)

    cadence_target =
      case feed.observed_interval do
        nil -> config(:default_interval)
        observed -> max(div(observed, 2), config(:min_interval))
      end

    max(max(server_min, ttl_min), cadence_target)
    |> clamp(config(:min_interval), config(:max_interval))
  end

  defp compute_interval(feed, response, :not_modified) do
    server_min = server_minimum(response)
    ttl_min = ttl_minimum(feed)

    # Compute current interval from last fetch, or use default
    current = current_interval(feed) || config(:default_interval)
    backed_off = trunc(current * config(:no_change_multiplier))

    ceiling =
      case feed.status do
        :dormant -> @dormant_ceiling
        _ -> config(:max_interval)
      end

    floor =
      case feed.status do
        :dormant -> @dormant_floor
        _ -> config(:min_interval)
      end

    max(max(server_min, ttl_min), backed_off)
    |> clamp(floor, ceiling)
  end

  defp compute_interval(feed, response, {:error, :rate_limited}) do
    # Retry-After takes absolute priority on 429
    retry_after = retry_after_seconds(response)

    if retry_after do
      clamp(retry_after, config(:min_interval), config(:error_max_interval))
    else
      # Aggressive backoff for rate limiting
      error_backoff(feed.error_count || 0, 60 * 60)
    end
  end

  defp compute_interval(feed, _response, {:error, :gone}) do
    # 410 Gone — use reprobe schedule
    reprobe_interval(feed.error_count || 0)
  end

  defp compute_interval(feed, response, {:error, _reason}) do
    # Check for Retry-After (sometimes present on 503)
    retry_after = retry_after_seconds(response)

    if retry_after do
      clamp(retry_after, config(:min_interval), config(:error_max_interval))
    else
      error_backoff(feed.error_count || 0, config(:error_base_interval))
    end
  end

  # --- Server signal extraction ---

  defp server_minimum(nil), do: 0

  defp server_minimum(%HTTPoison.Response{} = response) do
    HttpUtils.parse_max_age_from_response(response) || 0
  end

  defp retry_after_seconds(nil), do: nil

  defp retry_after_seconds(%HTTPoison.Response{} = response) do
    HttpUtils.parse_retry_after_from_response(response)
  end

  defp ttl_minimum(%Feed{ttl: nil}), do: 0
  defp ttl_minimum(%Feed{ttl: ttl}), do: ttl * 60

  # --- Backoff strategies ---

  defp error_backoff(error_count, base) do
    # Exponential backoff: base * 2^error_count, capped
    interval = base * Integer.pow(2, min(error_count, 10))
    clamp(interval, config(:error_base_interval), config(:error_max_interval))
  end

  defp reprobe_interval(attempt) do
    index = min(attempt, length(@reprobe_intervals) - 1)
    Enum.at(@reprobe_intervals, index)
  end

  # --- Health evaluation ---

  defp should_suspend?(%Feed{} = feed) do
    cond do
      # 410 Gone is an immediate suspension trigger
      feed.last_http_status == 410 ->
        true

      # Repeated 404 over threshold days
      feed.last_http_status == 404 and
          (feed.error_count || 0) >= @suspension_error_threshold ->
        days_since_success =
          if feed.last_new_item_at,
            do: DateTime.diff(DateTime.utc_now(), feed.last_new_item_at, :day),
            else: @suspension_404_days + 1

        days_since_success >= @suspension_404_days

      # Repeated parse/fetch failures
      (feed.error_count || 0) >= @suspension_error_threshold ->
        true

      true ->
        false
    end
  end

  defp should_go_dormant?(%Feed{} = feed) do
    case feed.last_new_item_at do
      nil ->
        false

      last_new ->
        days_quiet = DateTime.diff(DateTime.utc_now(), last_new, :day)

        threshold =
          case feed.observed_interval do
            nil ->
              @dormant_min_days

            observed ->
              max(div(observed * @dormant_cadence_multiplier, 86_400), @dormant_min_days)
          end

        days_quiet >= threshold
    end
  end

  # --- Utilities ---

  defp current_interval(%Feed{last_fetched_at: nil}), do: nil

  defp current_interval(%Feed{last_fetched_at: last_fetched, next_fetch: next_fetch})
       when not is_nil(next_fetch) do
    NaiveDateTime.diff(next_fetch, NaiveDateTime.from_iso8601!(DateTime.to_iso8601(last_fetched)))
  end

  defp current_interval(_feed), do: nil

  defp apply_jitter(interval) do
    jitter_range = div(interval * config(:jitter_percent), 100)

    if jitter_range > 0 do
      interval + :rand.uniform(jitter_range * 2 + 1) - jitter_range - 1
    else
      interval
    end
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  defp config(key) do
    case key do
      :default_interval -> config_get(:default_interval, @default_interval)
      :min_interval -> config_get(:min_interval, @min_interval)
      :max_interval -> config_get(:max_interval, @max_interval)
      :no_change_multiplier -> config_get(:no_change_multiplier, @no_change_multiplier)
      :error_base_interval -> config_get(:error_base_interval, @error_base_interval)
      :error_max_interval -> config_get(:error_max_interval, @error_max_interval)
      :jitter_percent -> config_get(:jitter_percent, @jitter_percent)
    end
  end

  defp config_get(key, default) do
    Application.get_env(:dashboard, __MODULE__, []) |> Keyword.get(key, default)
  end
end

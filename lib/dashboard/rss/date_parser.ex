defmodule Dashboard.RSS.DateParser do
  @moduledoc false

  def parse(nil), do: nil
  def parse(%DateTime{} = dt), do: to_utc_datetime(dt)
  def parse(%NaiveDateTime{} = ndt), do: to_utc_datetime(ndt)
  def parse(unix) when is_integer(unix) and unix > 0, do: to_utc_datetime(unix)

  def parse(value) when is_binary(value) do
    value = String.trim(value)

    if value == "" do
      nil
    else
      parse_iso8601(value) || parse_rfc2822(value)
    end
  end

  def parse(_), do: nil

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
end

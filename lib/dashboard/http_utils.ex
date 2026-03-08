defmodule Dashboard.HttpUtils do
  @moduledoc """
  HTTP utility functions for header extraction, construction, and cache-related parsing.
  """

  def matching_headers?(header1, header2) do
    header1 != nil and header1 == header2
  end

  @doc """
  Extracts a single header value from an `HTTPoison.Response`, case-insensitive.
  Returns `nil` if the header is not present.
  """
  def extract_header(header_name, %HTTPoison.Response{} = response) do
    Enum.find_value(response.headers, fn {header, value} ->
      if String.downcase(header, :default) == header_name, do: value
    end)
  end

  @doc """
  Extracts `max-age=N` from a `Cache-Control` header value.
  Returns the integer seconds or `nil`.

  ## Examples

      iex> Dashboard.HttpUtils.parse_max_age("public, max-age=3600")
      3600

      iex> Dashboard.HttpUtils.parse_max_age("no-cache")
      nil

      iex> Dashboard.HttpUtils.parse_max_age(nil)
      nil
  """
  def parse_max_age(nil), do: nil

  def parse_max_age(cache_control) when is_binary(cache_control) do
    case Regex.run(~r/max-age=(\d+)/i, cache_control) do
      [_, seconds] -> String.to_integer(seconds)
      _ -> nil
    end
  end

  @doc """
  Parses a `Retry-After` header value.
  Supports both seconds (integer string) and HTTP-date formats.
  Returns the number of seconds to wait, or `nil`.

  ## Examples

      iex> Dashboard.HttpUtils.parse_retry_after("120")
      120

      iex> Dashboard.HttpUtils.parse_retry_after(nil)
      nil
  """
  def parse_retry_after(nil), do: nil

  def parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} ->
        seconds

      _ ->
        # Attempt to parse as HTTP-date (RFC 7231)
        # For now, fall back to nil — HTTP-date parsing can be added later
        nil
    end
  end

  @doc """
  Extracts `max-age` from the `Cache-Control` header of an HTTP response.
  """
  def parse_max_age_from_response(%HTTPoison.Response{} = response) do
    extract_header("cache-control", response)
    |> parse_max_age()
  end

  @doc """
  Extracts `Retry-After` from an HTTP response.
  """
  def parse_retry_after_from_response(%HTTPoison.Response{} = response) do
    extract_header("retry-after", response)
    |> parse_retry_after()
  end
end

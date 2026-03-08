defmodule Dashboard.RSS.EntryNormalizer do
  @moduledoc false

  alias Dashboard.RSS.DateParser

  @spec normalize(binary(), map(), DateTime.t()) :: {:ok, map()} | :skip
  def normalize(feed_id, entry, now) when is_binary(feed_id) and is_map(entry) do
    guid = normalize_string(Map.get(entry, :guid) || Map.get(entry, :id))
    link = normalize_string(Map.get(entry, :link) || Map.get(entry, :url))
    title = normalize_string(Map.get(entry, :title))
    author = normalize_string(Map.get(entry, :author) || Map.get(entry, :dc_creator))
    summary = normalize_string(Map.get(entry, :summary) || Map.get(entry, :description))
    content = normalize_string(Map.get(entry, :content))

    published_at =
      DateParser.parse(
        Map.get(entry, :published_at) || Map.get(entry, :pub_date) || Map.get(entry, :published)
      )

    updated_at_feed =
      DateParser.parse(Map.get(entry, :updated_at_feed) || Map.get(entry, :updated))

    {identity_source, identity_key} =
      case {guid, link} do
        {guid_value, _} when is_binary(guid_value) and guid_value != "" ->
          {"guid", guid_value}

        {_, link_value} when is_binary(link_value) and link_value != "" ->
          {"link", link_value}

        _ ->
          {"fingerprint", build_fingerprint(title, published_at, author, summary, content)}
      end

    if weak_identity?(identity_source, identity_key) do
      :skip
    else
      {:ok,
       %{
         identity_source: identity_source,
         identity_key: identity_key,
         identity_hash: hash_identity(feed_id, identity_source, identity_key),
         guid: guid,
         link: link,
         title: title,
         author: author,
         summary: summary,
         content: content,
         published_at: published_at,
         updated_at_feed: updated_at_feed,
         first_seen_at: now,
         last_seen_at: now,
         inserted_at: now,
         updated_at: now,
         enclosures: normalize_enclosures(extract_enclosures(entry))
       }}
    end
  end

  def normalize(_, _, _), do: :skip

  defp weak_identity?("fingerprint", key), do: is_nil(key) or String.trim(key) == ""
  defp weak_identity?(_, _), do: false

  defp extract_enclosures(entry) when is_map(entry) do
    case Map.get(entry, :enclosures) || Map.get(entry, :enclosure) do
      nil -> extract_enclosures_from_links(Map.get(entry, :links))
      value -> value
    end
  end

  defp extract_enclosures(_), do: []

  defp extract_enclosures_from_links(links) when is_list(links) do
    links
    |> Enum.filter(fn link ->
      rel = normalize_string(Map.get(link, :rel) || Map.get(link, "rel"))
      rel == "enclosure"
    end)
    |> Enum.map(fn link ->
      %{
        url: Map.get(link, :href) || Map.get(link, "href"),
        type: Map.get(link, :type) || Map.get(link, "type"),
        length: Map.get(link, :length) || Map.get(link, "length")
      }
    end)
  end

  defp extract_enclosures_from_links(_), do: []

  defp normalize_enclosures(enclosures) when is_list(enclosures) do
    enclosures
    |> Enum.map(&normalize_enclosure/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp normalize_enclosures(enclosure) when is_map(enclosure),
    do: normalize_enclosures([enclosure])

  defp normalize_enclosures(_), do: []

  defp normalize_enclosure(enclosure) when is_map(enclosure) do
    url = normalize_string(Map.get(enclosure, :url) || Map.get(enclosure, "url"))

    if is_nil(url) do
      nil
    else
      %{
        url: url,
        media_type:
          normalize_string(
            Map.get(enclosure, :type) || Map.get(enclosure, "type") ||
              Map.get(enclosure, :media_type) || Map.get(enclosure, "media_type")
          ),
        length_bytes:
          normalize_int(
            Map.get(enclosure, :length) || Map.get(enclosure, "length") ||
              Map.get(enclosure, :length_bytes) || Map.get(enclosure, "length_bytes")
          )
      }
    end
  end

  defp normalize_enclosure(_), do: nil

  defp build_fingerprint(title, published_at, author, summary, content) do
    summary_digest = digest(summary)
    content_digest = digest(content)

    published_string =
      case published_at do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        _ -> ""
      end

    fields = [title, published_string, author, summary_digest, content_digest]

    strong_fields =
      Enum.count(fields, fn value ->
        is_binary(value) and String.trim(value) != ""
      end)

    if strong_fields < 2 do
      ""
    else
      fields
      |> Enum.map(&normalize_string_for_key/1)
      |> Enum.join("|")
    end
  end

  defp digest(nil), do: ""

  defp digest(value) when is_binary(value) do
    if String.trim(value) == "" do
      ""
    else
      :crypto.hash(:sha256, value)
      |> Base.encode16(case: :lower)
    end
  end

  defp digest(_), do: ""

  defp hash_identity(feed_id, identity_source, identity_key) do
    :crypto.hash(:sha256, "#{feed_id}:#{identity_source}:#{identity_key}")
    |> Base.encode16(case: :lower)
  end

  defp normalize_string_for_key(nil), do: ""

  defp normalize_string_for_key(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_string_for_key(value), do: normalize_string(value) || ""

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value) when is_integer(value) or is_float(value) or is_atom(value) do
    value
    |> to_string()
    |> normalize_string()
  end

  defp normalize_string(_), do: nil

  defp normalize_int(nil), do: nil
  defp normalize_int(value) when is_integer(value), do: value

  defp normalize_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_int(_), do: nil
end

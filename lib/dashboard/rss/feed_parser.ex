defmodule Dashboard.RSS.FeedParser do
  @moduledoc false

  @content_encoded_regex ~r/<(?:\w+:)?encoded\b[^>]*>(.*?)<\/(?:\w+:)?encoded>/is
  @item_regex ~r/<item\b[^>]*>(.*?)<\/item>/is
  @cdata_regex ~r/^\s*<!\[CDATA\[(.*)\]\]>\s*$/is

  @spec parse_string(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse_string(xml, opts \\ []) when is_binary(xml) and is_list(opts) do
    with {:ok, parsed} <- Gluttony.parse_string(xml, opts) do
      {:ok, maybe_enrich_rss_entries(parsed, xml)}
    end
  end

  defp maybe_enrich_rss_entries(%{type: :rss2, entries: entries} = parsed, xml)
       when is_list(entries) do
    content_list = extract_rss_content_encoded(xml)
    entries = merge_content(entries, content_list)
    %{parsed | entries: entries}
  end

  defp maybe_enrich_rss_entries(parsed, _xml), do: parsed

  defp extract_rss_content_encoded(xml) when is_binary(xml) do
    @item_regex
    |> Regex.scan(xml, capture: :all_but_first)
    |> Enum.map(fn
      [item_xml] -> extract_content_encoded_from_item(item_xml)
      _ -> nil
    end)
  end

  defp extract_content_encoded_from_item(item_xml) do
    case Regex.run(@content_encoded_regex, item_xml, capture: :all_but_first) do
      [content] -> normalize_content(content)
      _ -> nil
    end
  end

  defp normalize_content(content) when is_binary(content) do
    normalized =
      case Regex.run(@cdata_regex, content, capture: :all_but_first) do
        [cdata_content] -> cdata_content
        _ -> content
      end
      |> String.trim()

    if normalized == "", do: nil, else: normalized
  end

  defp merge_content(entries, content_list) do
    Enum.with_index(entries)
    |> Enum.map(fn {entry, index} ->
      case Enum.at(content_list, index) do
        nil -> entry
        content -> Map.put(entry, :content, content)
      end
    end)
  end
end

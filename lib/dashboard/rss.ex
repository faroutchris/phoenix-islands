defmodule Dashboard.RSS do
  @moduledoc """
  The RSS context.
  """

  import Ecto.Query, warn: false
  alias Dashboard.Repo
  alias Ecto.Multi

  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FeedEntry
  alias Dashboard.RSS.FeedEntryEnclosure
  alias Dashboard.RSS.IngestService

  @doc """
  Subscribes to a new feed by URL and immediately fetches it.

  ## Examples

      iex> subscribe("https://example.com/rss")
      {:ok, %Feed{}}

  """
  def subscribe(url) when is_binary(url) do
    if feed = Repo.get_by(Feed, url: url) do
      IngestService.update_pipeline(feed)
    else
      with {:ok, %Feed{} = feed} <- create_feed(%{url: url, title: url}) do
        IngestService.update_pipeline(feed)
      end
    end
  end

  @doc """
  Returns the list of feed.

  ## Examples

      iex> list_feed()
      [%Feed{}, ...]

  """
  def list_feed do
    Repo.all(Feed)
  end

  def list_feed(:due_for_update) do
    now = DateTime.utc_now()

    from(f in Feed,
      where: f.status in [:active, :dormant],
      where: f.next_fetch <= ^now or is_nil(f.next_fetch),
      order_by: [asc: f.next_fetch]
    )
    |> Repo.all()
  end

  def list_feed(:suspended_for_reprobe) do
    now = DateTime.utc_now()

    from(f in Feed,
      where: f.status == :suspended,
      where: f.next_fetch <= ^now
    )
    |> Repo.all()
  end

  def upsert_feed(%Ecto.Changeset{} = changeset) do
    Repo.insert_or_update(changeset)
  end

  def upsert_feed(attrs) do
    %Feed{}
    |> Feed.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def upsert_feed_with_entries(%Feed{} = feed, feed_attrs, entries) when is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.update(:feed, Feed.changeset(feed, feed_attrs))
    |> Multi.run(:entries, fn repo, _changes ->
      upsert_feed_entries(repo, feed.id, entries, now)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{feed: updated_feed}} -> {:ok, updated_feed}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def list_feed_entries(feed_id) when is_binary(feed_id) do
    from(e in FeedEntry,
      where: e.feed_id == ^feed_id,
      order_by: [desc: e.published_at, desc: e.inserted_at],
      preload: [:enclosures]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single feed.

  Raises `Ecto.NoResultsError` if the Feed does not exist.

  ## Examples

      iex> get_feed!(123)
      %Feed{}

      iex> get_feed!(456)
      ** (Ecto.NoResultsError)

  """
  def get_feed!(id), do: Repo.get!(Feed, id)

  @doc """
  Creates a feed.

  ## Examples

      iex> create_feed(%{field: value})
      {:ok, %Feed{}}

      iex> create_feed(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_feed(attrs) do
    %Feed{}
    |> Feed.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a feed.

  ## Examples

      iex> update_feed(feed, %{field: new_value})
      {:ok, %Feed{}}

      iex> update_feed(feed, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_feed(%Feed{} = feed, attrs) do
    feed
    |> Feed.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a feed.

  ## Examples

      iex> delete_feed(feed)
      {:ok, %Feed{}}

      iex> delete_feed(feed)
      {:error, %Ecto.Changeset{}}

  """
  def delete_feed(%Feed{} = feed) do
    Repo.delete(feed)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking feed changes.

  ## Examples

      iex> change_feed(feed)
      %Ecto.Changeset{data: %Feed{}}

  """
  def change_feed(%Feed{} = feed, attrs \\ %{}) do
    Feed.changeset(feed, attrs)
  end

  defp upsert_feed_entries(repo, feed_id, entries, now) do
    normalized_entries =
      entries
      |> Enum.map(&normalize_entry(feed_id, &1, now))
      |> Enum.reject(&is_nil/1)

    if normalized_entries == [] do
      {:ok, []}
    else
      insert_rows = Enum.map(normalized_entries, &Map.take(&1, feed_entry_insert_fields()))

      {_, returned_entries} =
        repo.insert_all(
          FeedEntry,
          insert_rows,
          on_conflict: {:replace, feed_entry_update_fields(now)},
          conflict_target: [:feed_id, :identity_hash],
          returning: [:id, :feed_id, :identity_hash]
        )

      enclosure_map =
        normalized_entries
        |> Map.new(fn entry -> {entry.identity_hash, entry.enclosures} end)

      Enum.each(returned_entries, fn row ->
        replace_enclosures(repo, row.id, Map.get(enclosure_map, row.identity_hash, []), now)
      end)

      {:ok, returned_entries}
    end
  end

  defp normalize_entry(feed_id, entry, now) when is_map(entry) do
    guid = normalize_string(Map.get(entry, :guid) || Map.get(entry, :id))
    link = normalize_string(Map.get(entry, :link) || Map.get(entry, :url))
    title = normalize_string(Map.get(entry, :title))
    author = normalize_string(Map.get(entry, :author) || Map.get(entry, :dc_creator))
    published_at = Map.get(entry, :published_at)
    updated_at_feed = Map.get(entry, :updated_at_feed)
    summary = normalize_string(Map.get(entry, :summary) || Map.get(entry, :description))
    content = normalize_string(Map.get(entry, :content))

    {identity_source, identity_key} =
      case {guid, link} do
        {guid, _} when is_binary(guid) and guid != "" -> {"guid", guid}
        {_, link} when is_binary(link) and link != "" -> {"link", link}
        _ -> {"fingerprint", build_fingerprint(title, published_at, author)}
      end

    identity_hash = hash_identity(feed_id, identity_source, identity_key)

    %{
      feed_id: feed_id,
      identity_source: identity_source,
      identity_key: identity_key,
      identity_hash: identity_hash,
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
    }
  end

  defp normalize_entry(_, _, _), do: nil

  defp extract_enclosures(entry) when is_map(entry) do
    case Map.get(entry, :enclosures) || Map.get(entry, :enclosure) do
      nil ->
        extract_enclosures_from_links(Map.get(entry, :links))

      value ->
        value
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
    |> Enum.map(fn enclosure ->
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
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.url)
  end

  defp normalize_enclosures(enclosure) when is_map(enclosure) do
    normalize_enclosures([enclosure])
  end

  defp normalize_enclosures(_), do: []

  defp replace_enclosures(repo, entry_id, enclosures, now) do
    urls = Enum.map(enclosures, & &1.url)

    delete_query =
      if urls == [] do
        from(e in FeedEntryEnclosure, where: e.feed_entry_id == ^entry_id)
      else
        from(e in FeedEntryEnclosure,
          where: e.feed_entry_id == ^entry_id and e.url not in ^urls
        )
      end

    repo.delete_all(delete_query)

    if enclosures != [] do
      rows =
        Enum.map(enclosures, fn enclosure ->
          %{
            feed_entry_id: entry_id,
            url: enclosure.url,
            media_type: enclosure.media_type,
            length_bytes: enclosure.length_bytes,
            inserted_at: now,
            updated_at: now
          }
        end)

      repo.insert_all(
        FeedEntryEnclosure,
        rows,
        on_conflict: {:replace, [:media_type, :length_bytes, :updated_at]},
        conflict_target: [:feed_entry_id, :url]
      )
    end
  end

  defp build_fingerprint(title, published_at, author) do
    published_string =
      case published_at do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        _ -> ""
      end

    [title || "", published_string, author || ""]
    |> Enum.map(&String.trim(String.downcase(&1)))
    |> Enum.join("|")
  end

  defp hash_identity(feed_id, identity_source, identity_key) do
    :crypto.hash(:sha256, "#{feed_id}:#{identity_source}:#{identity_key}")
    |> Base.encode16(case: :lower)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value |> to_string() |> normalize_string()

  defp normalize_int(nil), do: nil
  defp normalize_int(value) when is_integer(value), do: value

  defp normalize_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_int(_), do: nil

  defp feed_entry_insert_fields do
    [
      :feed_id,
      :identity_source,
      :identity_key,
      :identity_hash,
      :guid,
      :link,
      :title,
      :author,
      :summary,
      :content,
      :published_at,
      :updated_at_feed,
      :first_seen_at,
      :last_seen_at,
      :inserted_at,
      :updated_at
    ]
  end

  defp feed_entry_update_fields(_now) do
    [
      :title,
      :author,
      :summary,
      :content,
      :published_at,
      :updated_at_feed,
      :last_seen_at,
      :updated_at
    ]
  end
end

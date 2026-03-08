defmodule Dashboard.RSS do
  @moduledoc """
  The RSS context.
  """

  import Ecto.Query, warn: false
  alias Dashboard.Repo

  alias Dashboard.RSS.EntryStore
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
    EntryStore.upsert_feed_with_entries(feed, feed_attrs, entries)
  end

  def list_feed_entries(feed_id) when is_binary(feed_id) do
    list_feed_entries(feed_id, [])
  end

  def list_feed_entries(feed_id, opts) when is_binary(feed_id) and is_list(opts) do
    page = opts |> Keyword.get(:page, 1) |> normalize_page()
    page_size = opts |> Keyword.get(:page_size, 20) |> normalize_page_size()
    search = Keyword.get(opts, :search)
    has_enclosures = Keyword.get(opts, :has_enclosures)
    published_after = Keyword.get(opts, :published_after)
    published_before = Keyword.get(opts, :published_before)

    offset = (page - 1) * page_size

    FeedEntry
    |> where([e], e.feed_id == ^feed_id)
    |> maybe_filter_search(search)
    |> maybe_filter_has_enclosures(has_enclosures)
    |> maybe_filter_published_after(published_after)
    |> maybe_filter_published_before(published_before)
    |> order_by([e], desc: e.published_at, desc: e.inserted_at)
    |> limit(^page_size)
    |> offset(^offset)
    |> preload([:enclosures])
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

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) when is_binary(search) do
    pattern = "%#{search}%"
    where(query, [e], like(e.title, ^pattern) or like(e.summary, ^pattern))
  end

  defp maybe_filter_has_enclosures(query, nil), do: query

  defp maybe_filter_has_enclosures(query, true) do
    enclosure_entry_ids = from(en in FeedEntryEnclosure, select: en.feed_entry_id)
    where(query, [e], e.id in subquery(enclosure_entry_ids))
  end

  defp maybe_filter_has_enclosures(query, false) do
    enclosure_entry_ids = from(en in FeedEntryEnclosure, select: en.feed_entry_id)
    where(query, [e], e.id not in subquery(enclosure_entry_ids))
  end

  defp maybe_filter_published_after(query, nil), do: query

  defp maybe_filter_published_after(query, %DateTime{} = dt),
    do: where(query, [e], e.published_at >= ^dt)

  defp maybe_filter_published_after(query, _), do: query

  defp maybe_filter_published_before(query, nil), do: query

  defp maybe_filter_published_before(query, %DateTime{} = dt),
    do: where(query, [e], e.published_at <= ^dt)

  defp maybe_filter_published_before(query, _), do: query

  defp normalize_page(value) when is_integer(value) and value > 0, do: value
  defp normalize_page(_), do: 1

  defp normalize_page_size(value) when is_integer(value) and value > 0 do
    min(value, 100)
  end

  defp normalize_page_size(_), do: 20
end

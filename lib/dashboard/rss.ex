defmodule Dashboard.RSS do
  @moduledoc """
  The RSS context.
  """
  @time_limit 60 * 60

  import Ecto.Query, warn: false
  alias Dashboard.Repo

  alias Dashboard.RSS.Feed
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
    {:ok, now} = DateTime.now("Etc/UTC")
    overdue = DateTime.add(now, -@time_limit, :second)

    from(
      feed_sources in Feed,
      where: feed_sources.updated_at < ^overdue,
      select: feed_sources
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
end

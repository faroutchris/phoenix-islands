defmodule Dashboard.RSSTest do
  use Dashboard.DataCase

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed

  describe "feed" do
    import Dashboard.RSSFixtures

    @invalid_attrs %{
      description: nil,
      title: nil,
      author: nil,
      last_modified: nil,
      etag: nil,
      next_fetch: nil,
      favicon: nil
    }

    test "list_feed/0 returns all feed" do
      feed = feed_fixture()
      assert RSS.list_feed() == [feed]
    end

    test "get_feed!/1 returns the feed with given id" do
      feed = feed_fixture()
      assert RSS.get_feed!(feed.id) == feed
    end

    test "create_feed/1 with valid data creates a feed" do
      valid_attrs = %{
        description: "some description",
        title: "some title",
        author: "some author",
        url: "https://example.com/feed.xml",
        last_modified: "some last_modified",
        etag: "some etag",
        next_fetch: ~U[2026-02-28 18:10:00Z],
        favicon: "some favicon"
      }

      assert {:ok, %Feed{} = feed} = RSS.create_feed(valid_attrs)
      assert feed.description == "some description"
      assert feed.title == "some title"
      assert feed.author == "some author"
      assert feed.last_modified == "some last_modified"
      assert feed.etag == "some etag"
      assert feed.next_fetch == ~U[2026-02-28 18:10:00Z]
      assert feed.favicon == "some favicon"
    end

    test "create_feed/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = RSS.create_feed(@invalid_attrs)
    end

    test "update_feed/2 with valid data updates the feed" do
      feed = feed_fixture()

      update_attrs = %{
        description: "some updated description",
        title: "some updated title",
        author: "some updated author",
        url: "https://example.com/updated-feed.xml",
        last_modified: "some updated last_modified",
        etag: "some updated etag",
        next_fetch: ~U[2026-03-01 18:10:00Z],
        favicon: "some updated favicon"
      }

      assert {:ok, %Feed{} = feed} = RSS.update_feed(feed, update_attrs)
      assert feed.description == "some updated description"
      assert feed.title == "some updated title"
      assert feed.author == "some updated author"
      assert feed.last_modified == "some updated last_modified"
      assert feed.etag == "some updated etag"
      assert feed.next_fetch == ~U[2026-03-01 18:10:00Z]
      assert feed.favicon == "some updated favicon"
    end

    test "update_feed/2 with invalid data returns error changeset" do
      feed = feed_fixture()
      assert {:error, %Ecto.Changeset{}} = RSS.update_feed(feed, @invalid_attrs)
      assert feed == RSS.get_feed!(feed.id)
    end

    test "delete_feed/1 deletes the feed" do
      feed = feed_fixture()
      assert {:ok, %Feed{}} = RSS.delete_feed(feed)
      assert_raise Ecto.NoResultsError, fn -> RSS.get_feed!(feed.id) end
    end

    test "change_feed/1 returns a feed changeset" do
      feed = feed_fixture()
      assert %Ecto.Changeset{} = RSS.change_feed(feed)
    end
  end

  describe "feed entries queries" do
    test "list_feed_entries/2 supports pagination and search" do
      feed = create_feed!("https://example.com/entries")

      assert {:ok, _updated_feed} =
               RSS.upsert_feed_with_entries(feed, %{}, [
                 %{
                   guid: "a",
                   title: "Alpha",
                   summary: "hello",
                   published_at: ~U[2026-03-01 10:00:00Z]
                 },
                 %{
                   guid: "b",
                   title: "Bravo",
                   summary: "world",
                   published_at: ~U[2026-03-02 10:00:00Z]
                 },
                 %{
                   guid: "c",
                   title: "Charlie",
                   summary: "hello world",
                   published_at: ~U[2026-03-03 10:00:00Z]
                 }
               ])

      page1 = RSS.list_feed_entries(feed.id, page: 1, page_size: 2)
      page2 = RSS.list_feed_entries(feed.id, page: 2, page_size: 2)

      assert length(page1) == 2
      assert length(page2) == 1

      search = RSS.list_feed_entries(feed.id, search: "hello")
      assert Enum.map(search, & &1.title) |> Enum.sort() == ["Alpha", "Charlie"]
    end

    test "list_feed_entries/2 filters by enclosures and published range" do
      feed = create_feed!("https://example.com/filters")

      assert {:ok, _updated_feed} =
               RSS.upsert_feed_with_entries(feed, %{}, [
                 %{
                   guid: "with-enclosure",
                   title: "With Enclosure",
                   published_at: ~U[2026-03-02 10:00:00Z],
                   enclosure: %{
                     url: "https://cdn.example/media.mp3",
                     type: "audio/mpeg",
                     length: "12"
                   }
                 },
                 %{
                   guid: "without-enclosure",
                   title: "Without Enclosure",
                   published_at: ~U[2026-03-01 10:00:00Z]
                 }
               ])

      with_enclosures = RSS.list_feed_entries(feed.id, has_enclosures: true)
      without_enclosures = RSS.list_feed_entries(feed.id, has_enclosures: false)

      assert Enum.map(with_enclosures, & &1.title) == ["With Enclosure"]
      assert Enum.map(without_enclosures, & &1.title) == ["Without Enclosure"]

      published_after = RSS.list_feed_entries(feed.id, published_after: ~U[2026-03-02 00:00:00Z])
      assert Enum.map(published_after, & &1.title) == ["With Enclosure"]
    end

    test "upsert_feed_with_entries/3 skips weak entries and dedupes same-batch identities" do
      feed = create_feed!("https://example.com/dedupe")

      assert {:ok, _updated_feed} =
               RSS.upsert_feed_with_entries(feed, %{}, [
                 %{},
                 %{guid: "dup-guid", title: "First Title", summary: "first"},
                 %{guid: "dup-guid", title: "Second Title", summary: "second"}
               ])

      entries = RSS.list_feed_entries(feed.id)
      assert length(entries) == 1
      assert hd(entries).title == "First Title"
    end
  end

  defp create_feed!(url) do
    {:ok, feed} = RSS.create_feed(%{title: "Feed", url: url})
    feed
  end
end

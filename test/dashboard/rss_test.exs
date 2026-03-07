defmodule Dashboard.RSSTest do
  use Dashboard.DataCase

  alias Dashboard.RSS

  describe "feed" do
    alias Dashboard.RSS.Feed

    import Dashboard.RSSFixtures

    @invalid_attrs %{description: nil, title: nil, author: nil, last_modified: nil, etag: nil, next_fetch: nil, favicon: nil}

    test "list_feed/0 returns all feed" do
      feed = feed_fixture()
      assert RSS.list_feed() == [feed]
    end

    test "get_feed!/1 returns the feed with given id" do
      feed = feed_fixture()
      assert RSS.get_feed!(feed.id) == feed
    end

    test "create_feed/1 with valid data creates a feed" do
      valid_attrs = %{description: "some description", title: "some title", author: "some author", last_modified: "some last_modified", etag: "some etag", next_fetch: ~N[2026-02-28 18:10:00], favicon: "some favicon"}

      assert {:ok, %Feed{} = feed} = RSS.create_feed(valid_attrs)
      assert feed.description == "some description"
      assert feed.title == "some title"
      assert feed.author == "some author"
      assert feed.last_modified == "some last_modified"
      assert feed.etag == "some etag"
      assert feed.next_fetch == ~N[2026-02-28 18:10:00]
      assert feed.favicon == "some favicon"
    end

    test "create_feed/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = RSS.create_feed(@invalid_attrs)
    end

    test "update_feed/2 with valid data updates the feed" do
      feed = feed_fixture()
      update_attrs = %{description: "some updated description", title: "some updated title", author: "some updated author", last_modified: "some updated last_modified", etag: "some updated etag", next_fetch: ~N[2026-03-01 18:10:00], favicon: "some updated favicon"}

      assert {:ok, %Feed{} = feed} = RSS.update_feed(feed, update_attrs)
      assert feed.description == "some updated description"
      assert feed.title == "some updated title"
      assert feed.author == "some updated author"
      assert feed.last_modified == "some updated last_modified"
      assert feed.etag == "some updated etag"
      assert feed.next_fetch == ~N[2026-03-01 18:10:00]
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
end

defmodule Dashboard.RSSEntrySchemasTest do
  use Dashboard.DataCase

  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FeedEntry
  alias Dashboard.RSS.FeedEntryEnclosure
  alias Dashboard.Repo

  test "feed entry changeset requires identity and feed" do
    changeset = FeedEntry.changeset(%FeedEntry{}, %{})

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).feed_id
    assert "can't be blank" in errors_on(changeset).identity_key
    assert "can't be blank" in errors_on(changeset).identity_hash
    assert "can't be blank" in errors_on(changeset).identity_source
    assert "can't be blank" in errors_on(changeset).first_seen_at
    assert "can't be blank" in errors_on(changeset).last_seen_at
  end

  test "feed entry has unique feed_id + identity_hash" do
    feed = create_feed!()

    attrs = %{
      feed_id: feed.id,
      identity_source: "guid",
      identity_key: "entry-1",
      identity_hash: "hash-1",
      first_seen_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now()
    }

    assert {:ok, _entry} = %FeedEntry{} |> FeedEntry.changeset(attrs) |> Repo.insert()

    assert {:error, changeset} = %FeedEntry{} |> FeedEntry.changeset(attrs) |> Repo.insert()
    assert "has already been taken" in errors_on(changeset).identity_hash
  end

  test "feed entry enclosure requires url and has unique feed_entry_id + url" do
    feed = create_feed!()

    {:ok, entry} =
      %FeedEntry{}
      |> FeedEntry.changeset(%{
        feed_id: feed.id,
        identity_source: "guid",
        identity_key: "entry-2",
        identity_hash: "hash-2",
        first_seen_at: DateTime.utc_now(),
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.insert()

    invalid_changeset =
      FeedEntryEnclosure.changeset(%FeedEntryEnclosure{}, %{feed_entry_id: entry.id})

    refute invalid_changeset.valid?
    assert "can't be blank" in errors_on(invalid_changeset).url

    enclosure_attrs = %{feed_entry_id: entry.id, url: "https://cdn.example/file.mp3"}

    assert {:ok, _} =
             %FeedEntryEnclosure{}
             |> FeedEntryEnclosure.changeset(enclosure_attrs)
             |> Repo.insert()

    assert {:error, changeset} =
             %FeedEntryEnclosure{}
             |> FeedEntryEnclosure.changeset(enclosure_attrs)
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).url
  end

  defp create_feed! do
    {:ok, feed} =
      %Feed{}
      |> Feed.changeset(%{
        title: "Feed",
        url: "https://example.com/#{System.unique_integer([:positive])}.xml"
      })
      |> Repo.insert()

    feed
  end
end

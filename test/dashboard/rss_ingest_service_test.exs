defmodule Dashboard.RSS.IngestServiceTest do
  use Dashboard.DataCase

  alias Dashboard.RSS
  alias Dashboard.RSS.Feed
  alias Dashboard.RSS.FeedEntry
  alias Dashboard.RSS.IngestService

  setup do
    previous_fetch_worker = Application.get_env(:dashboard, :rss_fetch_worker)
    previous_feed_parser = Application.get_env(:dashboard, :rss_feed_parser)

    Application.put_env(:dashboard, :rss_fetch_worker, __MODULE__.FakeFetchWorker)
    Application.put_env(:dashboard, :rss_feed_parser, __MODULE__.FakeParser)

    on_exit(fn ->
      restore_env(:rss_fetch_worker, previous_fetch_worker)
      restore_env(:rss_feed_parser, previous_feed_parser)
    end)

    :ok
  end

  test "update_pipeline/1 updates feed metadata on modified success" do
    feed = create_feed!("test://modified")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 200
    assert updated.title == "Parsed Feed"
    assert updated.description == "Parsed Description"
    assert updated.link == "https://parsed.example/feed"
    assert updated.ttl == 60
    assert updated.error_count == 0
    assert updated.miss_count == 0
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.last_new_item_at
    assert %DateTime{} = updated.next_fetch
    assert is_binary(updated.content_hash)
    assert String.length(updated.content_hash) == 64

    entries = RSS.list_feed_entries(updated.id)
    assert length(entries) == 1
  end

  test "update_pipeline/1 upserts entries deterministically and replaces enclosure set" do
    feed = create_feed!("test://entries")

    assert {:ok, %Feed{} = first_feed} = IngestService.update_pipeline(feed)
    first_entries = RSS.list_feed_entries(first_feed.id)
    assert length(first_entries) == 3

    guid_entry_first = Enum.find(first_entries, &(&1.identity_source == "guid"))
    assert guid_entry_first.guid == "guid-1"

    assert Enum.sort(Enum.map(guid_entry_first.enclosures, & &1.url)) ==
             Enum.sort(["https://cdn.example/a.mp3", "https://cdn.example/b.jpg"])

    reloaded_feed = RSS.get_feed!(first_feed.id)
    assert {:ok, %Feed{} = second_feed} = IngestService.update_pipeline(reloaded_feed)

    second_entries = RSS.list_feed_entries(second_feed.id)
    assert length(second_entries) == 3

    guid_entry_second = Enum.find(second_entries, &(&1.identity_source == "guid"))
    assert guid_entry_second.id == guid_entry_first.id
    assert guid_entry_second.first_seen_at == guid_entry_first.first_seen_at

    assert DateTime.compare(guid_entry_second.last_seen_at, guid_entry_first.last_seen_at) in [
             :eq,
             :gt
           ]

    assert guid_entry_second.title == "Guid Entry Updated"

    assert Enum.sort(Enum.map(guid_entry_second.enclosures, & &1.url)) ==
             Enum.sort(["https://cdn.example/a.mp3", "https://cdn.example/c.mp4"])

    fingerprint_entry = Enum.find(second_entries, &(&1.identity_source == "fingerprint"))
    assert %FeedEntry{} = fingerprint_entry
  end

  test "update_pipeline/1 does not mutate entries on not modified responses" do
    feed = create_feed!("test://entries_not_modified")

    assert {:ok, %Feed{} = first_feed} = IngestService.update_pipeline(feed)
    [entry] = RSS.list_feed_entries(first_feed.id)

    reloaded_feed = RSS.get_feed!(first_feed.id)
    assert {:ok, %Feed{} = _second_feed} = IngestService.update_pipeline(reloaded_feed)

    [entry_after] = RSS.list_feed_entries(first_feed.id)
    assert entry_after.id == entry.id
    assert entry_after.last_seen_at == entry.last_seen_at
  end

  test "update_pipeline/1 increments miss_count on not modified" do
    feed = create_feed!("test://not_modified", %{miss_count: 2, error_count: 4, etag: "etag-old"})

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 304
    assert updated.miss_count == 3
    assert updated.error_count == 0
    assert updated.status in [:active, :dormant]
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 stores canonical_url for redirects" do
    feed = create_feed!("test://redirect")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 301
    assert updated.canonical_url == "https://redirected.example/feed"
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
    assert DateTime.diff(updated.next_fetch, updated.last_fetched_at, :second) in 0..1
  end

  test "update_pipeline/1 records normalized http errors" do
    feed = create_feed!("test://not_found")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.last_http_status == 404
    assert updated.error_count == 1
    assert updated.status == :active
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 records network errors" do
    feed = create_feed!("test://network")

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.error_count == 1
    assert updated.status == :active
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  test "update_pipeline/1 handles parse failures as errors" do
    feed = create_feed!("test://parse_failure", %{title: "Original Title"})

    assert {:ok, %Feed{} = updated} = IngestService.update_pipeline(feed)

    assert updated.error_count == 1
    assert updated.status == :active
    assert updated.title == "Original Title"
    assert %DateTime{} = updated.last_fetched_at
    assert %DateTime{} = updated.next_fetch
  end

  defp create_feed!(url, attrs \\ %{}) do
    defaults = %{
      title: "Seed Feed",
      url: url,
      status: :active,
      miss_count: 0,
      error_count: 0
    }

    {:ok, feed} =
      defaults
      |> Map.merge(attrs)
      |> RSS.create_feed()

    feed
  end

  defp restore_env(key, nil), do: Application.delete_env(:dashboard, key)
  defp restore_env(key, value), do: Application.put_env(:dashboard, key, value)

  defmodule FakeFetchWorker do
    alias Dashboard.RSS.Feed

    def fetch_feed(%Feed{url: "test://modified"} = feed) do
      response = %HTTPoison.Response{
        status_code: 200,
        headers: [{"etag", "etag-new"}, {"last-modified", "Tue, 03 Mar 2026 10:00:00 GMT"}],
        body: "<rss />"
      }

      {:ok, feed, response}
    end

    def fetch_feed(%Feed{url: "test://entries"} = feed) do
      body = if is_nil(feed.content_hash), do: "<entries-v1 />", else: "<entries-v2 />"
      response = %HTTPoison.Response{status_code: 200, headers: [], body: body}
      {:ok, feed, response}
    end

    def fetch_feed(%Feed{url: "test://entries_not_modified"} = feed) do
      if is_nil(feed.content_hash) do
        response = %HTTPoison.Response{status_code: 200, headers: [], body: "<entries-single />"}
        {:ok, feed, response}
      else
        response = %HTTPoison.Response{status_code: 304, headers: []}
        {:not_modified, feed, response}
      end
    end

    def fetch_feed(%Feed{url: "test://parse_failure"} = feed) do
      response = %HTTPoison.Response{status_code: 200, headers: [], body: "<bad />"}
      {:ok, feed, response}
    end

    def fetch_feed(%Feed{url: "test://not_modified"} = feed) do
      response = %HTTPoison.Response{status_code: 304, headers: []}
      {:not_modified, feed, response}
    end

    def fetch_feed(%Feed{url: "test://redirect"} = feed) do
      response = %HTTPoison.Response{
        status_code: 301,
        headers: [{"location", "https://redirected.example/feed"}]
      }

      {:redirect, feed, "https://redirected.example/feed", response}
    end

    def fetch_feed(%Feed{url: "test://not_found"} = feed) do
      response = %HTTPoison.Response{status_code: 404, headers: []}
      {:not_found, feed, response}
    end

    def fetch_feed(%Feed{url: "test://network"} = feed) do
      {:error, feed, :econnrefused}
    end
  end

  defmodule FakeParser do
    def parse_string("<rss />") do
      {:ok,
       %{
         feed: %{
           title: "Parsed Feed",
           description: "Parsed Description",
           link: "https://parsed.example/feed",
           ttl: "60"
         },
         entries: [
           %{
             guid: "guid-modified-1",
             title: "Entry",
             pub_date: "Tue, 03 Mar 2026 10:00:00 GMT",
             enclosure: %{
               url: "https://cdn.example/media.mp3",
               type: "audio/mpeg",
               length: "1234"
             }
           }
         ]
       }}
    end

    def parse_string("<entries-v1 />") do
      {:ok,
       %{
         feed: %{title: "Entries Feed", description: "v1", link: "https://example.com/entries"},
         entries: [
           %{
             guid: "guid-1",
             title: "Guid Entry",
             author: "Author One",
             pub_date: "Tue, 03 Mar 2026 10:00:00 GMT",
             enclosure: [
               %{url: "https://cdn.example/a.mp3", type: "audio/mpeg", length: "1000"},
               %{url: "https://cdn.example/b.jpg", type: "image/jpeg", length: "2000"}
             ]
           },
           %{
             link: "https://example.com/posts/2",
             title: "Link Entry",
             author: "Author Two",
             pub_date: "Mon, 02 Mar 2026 10:00:00 GMT",
             enclosure: %{url: "https://cdn.example/l1.mp4", type: "video/mp4", length: "4000"}
           },
           %{
             title: "Fingerprint Entry",
             author: "Author Three",
             pub_date: "Sun, 01 Mar 2026 10:00:00 GMT",
             summary: "No guid or link"
           }
         ]
       }}
    end

    def parse_string("<entries-v2 />") do
      {:ok,
       %{
         feed: %{title: "Entries Feed", description: "v2", link: "https://example.com/entries"},
         entries: [
           %{
             guid: "guid-1",
             title: "Guid Entry Updated",
             author: "Author One",
             pub_date: "Tue, 03 Mar 2026 10:00:00 GMT",
             updated: "2026-03-03T12:00:00Z",
             enclosure: [
               %{url: "https://cdn.example/a.mp3", type: "audio/mpeg", length: "1500"},
               %{url: "https://cdn.example/c.mp4", type: "video/mp4", length: "5000"}
             ]
           },
           %{
             link: "https://example.com/posts/2",
             title: "Link Entry Updated",
             author: "Author Two",
             pub_date: "Mon, 02 Mar 2026 10:00:00 GMT"
           }
         ]
       }}
    end

    def parse_string("<entries-single />") do
      {:ok,
       %{
         feed: %{
           title: "Single Entry Feed",
           description: "single",
           link: "https://example.com/single"
         },
         entries: [
           %{
             guid: "guid-single",
             title: "Single Entry",
             pub_date: "Tue, 03 Mar 2026 10:00:00 GMT"
           }
         ]
       }}
    end

    def parse_string("<bad />"), do: {:error, :invalid}
  end
end

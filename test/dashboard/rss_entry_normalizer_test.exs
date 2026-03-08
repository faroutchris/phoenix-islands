defmodule Dashboard.RSSEntryNormalizerTest do
  use ExUnit.Case, async: true

  alias Dashboard.RSS.EntryNormalizer

  test "normalize/3 skips weak fingerprint entries" do
    now = ~U[2026-03-08 14:00:00Z]

    assert :skip == EntryNormalizer.normalize(Ecto.UUID.generate(), %{}, now)
  end

  test "normalize/3 uses guid identity and normalizes singular enclosure" do
    feed_id = Ecto.UUID.generate()
    now = ~U[2026-03-08 14:00:00Z]

    entry = %{
      guid: "entry-guid-1",
      title: "Episode 1",
      enclosure: %{url: "https://cdn.example/ep1.mp3", type: "audio/mpeg", length: "123"}
    }

    assert {:ok, normalized} = EntryNormalizer.normalize(feed_id, entry, now)
    assert normalized.identity_source == "guid"
    assert normalized.identity_key == "entry-guid-1"
    assert length(normalized.enclosures) == 1
    assert hd(normalized.enclosures).url == "https://cdn.example/ep1.mp3"
    assert hd(normalized.enclosures).length_bytes == 123
  end

  test "normalize/3 extracts atom-style enclosure links" do
    feed_id = Ecto.UUID.generate()
    now = ~U[2026-03-08 14:00:00Z]

    entry = %{
      link: "https://example.com/posts/1",
      links: [
        %{rel: "alternate", href: "https://example.com/posts/1"},
        %{
          rel: "enclosure",
          href: "https://cdn.example/video.mp4",
          type: "video/mp4",
          length: "999"
        }
      ]
    }

    assert {:ok, normalized} = EntryNormalizer.normalize(feed_id, entry, now)
    assert normalized.identity_source == "link"
    assert Enum.map(normalized.enclosures, & &1.url) == ["https://cdn.example/video.mp4"]
  end

  test "normalize/3 does not crash on non-string nested fields" do
    feed_id = Ecto.UUID.generate()
    now = ~U[2026-03-08 14:00:00Z]

    entry = %{guid: "safe-guid", title: %{text: "bad-shape"}, summary: [1, 2, 3]}

    assert {:ok, normalized} = EntryNormalizer.normalize(feed_id, entry, now)
    assert normalized.guid == "safe-guid"
    assert normalized.title == nil
    assert normalized.summary == nil
  end
end

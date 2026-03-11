defmodule Dashboard.RSSFeedParserTest do
  use ExUnit.Case, async: true

  alias Dashboard.RSS.FeedParser

  test "parse_string/2 enriches rss entries with content:encoded" do
    xml = """
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
      <channel>
        <title>Feed</title>
        <link>https://example.com</link>
        <description>Desc</description>
        <item>
          <title>Item 1</title>
          <link>https://example.com/1</link>
          <description>Summary 1</description>
          <content:encoded><![CDATA[<p>Full 1</p>]]></content:encoded>
        </item>
        <item>
          <title>Item 2</title>
          <link>https://example.com/2</link>
          <description>Summary 2</description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, %{type: :rss2, entries: [first, second]}} = FeedParser.parse_string(xml)
    assert first.content == "<p>Full 1</p>"
    assert second[:content] == nil
  end

  test "parse_string/2 keeps atom content untouched" do
    xml = """
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Feed</title>
      <id>feed-1</id>
      <updated>2026-03-11T00:00:00Z</updated>
      <entry>
        <id>entry-1</id>
        <title>Item 1</title>
        <updated>2026-03-11T00:00:00Z</updated>
        <content type="html"><![CDATA[<p>Full atom</p>]]></content>
      </entry>
    </feed>
    """

    assert {:ok, %{type: :atom1, entries: [entry]}} = FeedParser.parse_string(xml)
    assert entry.content == "<p>Full atom</p>"
  end
end

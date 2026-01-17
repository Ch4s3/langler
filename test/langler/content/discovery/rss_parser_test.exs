defmodule Langler.Content.Discovery.RssParserTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Discovery.RssParser

  test "parses RSS items with relative links" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <title><![CDATA[Test Article]]></title>
          <link>/articles/1</link>
          <description><![CDATA[Summary]]></description>
          <pubDate>2024-01-01T00:00:00Z</pubDate>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.url == "https://example.com/articles/1"
    assert entry.title == "Test Article"
    assert entry.summary == "Summary"

    assert entry.published_at == nil
  end

  test "falls back to Atom entries when RSS items are missing" do
    feed = """
    <feed>
      <entry>
        <title>Atom Title</title>
        <link href="/post/9" />
        <summary>Atom summary</summary>
        <updated>2024-01-02T12:00:00Z</updated>
      </entry>
    </feed>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.url == "https://example.com/post/9"
    assert entry.title == "Atom Title"
    assert entry.summary == "Atom summary"

    assert {:ok, expected, 0} = DateTime.from_iso8601("2024-01-02T12:00:00Z")
    assert entry.published_at == expected
  end
end

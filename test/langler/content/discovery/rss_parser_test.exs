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

  test "handles invalid XML" do
    invalid_xml = "<rss><invalid>"
    assert {:ok, []} = RssParser.parse(invalid_xml, "https://example.com")
  end

  test "filters out entries without valid links" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Valid</title>
          <link>/valid</link>
        </item>
        <item>
          <title>Invalid</title>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.url == "https://example.com/valid"
  end

  test "handles Atom entries with link text instead of href" do
    feed = """
    <feed>
      <entry>
        <title>Atom Entry</title>
        <link>https://example.com/post/10</link>
        <summary>Summary</summary>
      </entry>
    </feed>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.url == "https://example.com/post/10"
  end

  test "handles HTML in description" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Test</title>
          <link>/article</link>
          <description><![CDATA[<p>HTML <strong>content</strong></p>]]></description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.summary == "<p>HTML <strong>content</strong></p>"
  end

  test "handles missing optional fields" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <link>/article</link>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.url == "https://example.com/article"
    assert entry.title == nil
    assert entry.summary == nil
  end

  test "uses content as fallback for Atom summary" do
    feed = """
    <feed>
      <entry>
        <title>Entry</title>
        <link href="/post" />
        <content>Content text</content>
      </entry>
    </feed>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.summary == "Content text"
  end

  test "handles whitespace in text fields" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <title>   Test   Title   </title>
          <link>/article</link>
          <description>   Summary   with   spaces   </description>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.title == "Test Title"
    assert entry.summary == "Summary with spaces"
  end

  test "handles invalid date formats gracefully" do
    feed = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Test</title>
          <link>/article</link>
          <pubDate>Invalid Date Format</pubDate>
        </item>
      </channel>
    </rss>
    """

    assert {:ok, [entry]} = RssParser.parse(feed, "https://example.com")
    assert entry.published_at == nil
  end
end

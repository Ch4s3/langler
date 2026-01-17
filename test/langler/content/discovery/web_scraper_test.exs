defmodule Langler.Content.Discovery.WebScraperTest do
  use ExUnit.Case, async: true

  alias Langler.Content.Discovery.WebScraper

  test "scrapes and normalizes links with allow/deny patterns" do
    html = """
    <html>
      <body>
        <div class="posts">
          <a href="/article-1">First</a>
          <a href="https://example.com/article-2">Second</a>
          <a href="/ignore-me">Ignore</a>
        </div>
      </body>
    </html>
    """

    config = %{
      "list_selector" => ".posts",
      "link_selector" => "a[href]",
      "allow_patterns" => ["article"],
      "deny_patterns" => ["ignore"]
    }

    assert {:ok, entries} = WebScraper.scrape(html, "https://example.com", config)

    assert Enum.map(entries, & &1.url) == [
             "https://example.com/article-1",
             "https://example.com/article-2"
           ]
  end

  test "returns an empty list when no links are found" do
    html = "<html><body><div>No links here</div></body></html>"

    assert {:ok, []} = WebScraper.scrape(html, "https://example.com", %{})
  end
end

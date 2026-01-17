defmodule Langler.Content.Discovery.DiscovererTest do
  use Langler.DataCase, async: false

  alias Langler.Content
  alias Langler.Content.Discovery.Discoverer
  alias Langler.Content.SourceSite

  setup do
    original = Req.default_options()
    Req.default_options(plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      Req.default_options(original)
    end)

    :ok
  end

  defp create_source_site(attrs) do
    base_attrs = %{
      name: "Example",
      url: "http://example.test",
      discovery_method: "rss",
      language: "spanish"
    }

    {:ok, site} = Content.create_source_site(Map.merge(base_attrs, attrs))
    site
  end

  test "returns an error for invalid discovery method" do
    assert {:error, :invalid_discovery_method} =
             Discoverer.discover(%SourceSite{discovery_method: "invalid"})
  end

  test "discovers articles via RSS" do
    rss_xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>First</title>
          <link>/article-1</link>
          <description>Summary</description>
          <pubDate>2024-01-01T00:00:00Z</pubDate>
        </item>
      </channel>
    </rss>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/rss" -> Req.Test.text(conn, rss_xml)
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    site =
      create_source_site(%{
        rss_url: "http://example.test/rss"
      })

    assert {:ok, 1} = Discoverer.discover(site)

    assert Content.get_discovered_article_by_url("http://example.test/article-1")
    refreshed = Content.get_source_site!(site.id)
    assert refreshed.last_checked_at
  end

  test "discovers articles via scraping" do
    html = """
    <html>
      <body>
        <div class="posts">
          <a href="/article-2">Second</a>
        </div>
      </body>
    </html>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/page" -> Req.Test.html(conn, html)
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    site =
      create_source_site(%{
        url: "http://example.test/page",
        discovery_method: "scraping",
        scraping_config: %{
          "list_selector" => ".posts",
          "link_selector" => "a[href]"
        }
      })

    assert {:ok, 1} = Discoverer.discover(site)
    assert Content.get_discovered_article_by_url("http://example.test/article-2")
  end

  test "handles 304 Not Modified response" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.put_resp_header(conn, "etag", "test-etag")
      |> Plug.Conn.send_resp(304, "")
    end)

    site =
      create_source_site(%{
        rss_url: "http://example.test/rss",
        etag: "test-etag"
      })

    assert {:ok, 0} = Discoverer.discover(site)
    refreshed = Content.get_source_site!(site.id)
    assert refreshed.last_checked_at
  end

  test "handles HTTP errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 500, "")
    end)

    site = create_source_site(%{rss_url: "http://example.test/rss"})

    assert {:error, {:http_error, 500}} = Discoverer.discover(site)
    refreshed = Content.get_source_site!(site.id)
    assert refreshed.last_error
  end

  test "handles network errors" do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    site = create_source_site(%{rss_url: "http://example.test/rss"})

    assert {:error, _} = Discoverer.discover(site)
    refreshed = Content.get_source_site!(site.id)
    assert refreshed.last_error
  end

  test "discovers via hybrid method (RSS first)" do
    rss_xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>RSS Article</title>
          <link>/article-rss</link>
          <description>RSS Summary</description>
        </item>
      </channel>
    </rss>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/rss" -> Req.Test.text(conn, rss_xml)
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    site =
      create_source_site(%{
        rss_url: "http://example.test/rss",
        discovery_method: "hybrid"
      })

    assert {:ok, 1} = Discoverer.discover(site)
  end

  test "discovers via hybrid method (falls back to scraping)" do
    html = """
    <html>
      <body>
        <div class="posts">
          <a href="/article-scrape">Scraped</a>
        </div>
      </body>
    </html>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/rss" -> Plug.Conn.send_resp(conn, 404, "")
        "/page" -> Req.Test.html(conn, html)
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    site =
      create_source_site(%{
        url: "http://example.test/page",
        rss_url: "http://example.test/rss",
        discovery_method: "hybrid",
        scraping_config: %{
          "list_selector" => ".posts",
          "link_selector" => "a[href]"
        }
      })

    assert {:ok, 1} = Discoverer.discover(site)
    assert Content.get_discovered_article_by_url("http://example.test/article-scrape")
  end

  test "uses source site URL when rss_url is nil" do
    rss_xml = """
    <rss version="2.0">
      <channel>
        <item>
          <title>Article</title>
          <link>/article</link>
        </item>
      </channel>
    </rss>
    """

    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/" -> Req.Test.text(conn, rss_xml)
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    site =
      create_source_site(%{
        url: "http://example.test/",
        rss_url: nil
      })

    assert {:ok, 1} = Discoverer.discover(site)
  end
end

defmodule Langler.Content.Discovery.Discoverer do
  @moduledoc """
  Orchestrates the discovery process for a source site.
  Handles RSS, scraping, and hybrid methods.
  """

  alias Langler.Content.SourceSite
  alias Langler.Content.Discovery.{RssParser, WebScraper}

  @doc """
  Discovers articles from a source site.
  Returns `{:ok, count}` where count is the number of new articles discovered.
  """
  @spec discover(SourceSite.t()) :: {:ok, integer()} | {:error, term()}
  def discover(%SourceSite{} = source_site) do
    case source_site.discovery_method do
      "rss" -> discover_from_rss(source_site)
      "scraping" -> discover_from_scraping(source_site)
      "hybrid" -> discover_hybrid(source_site)
      _ -> {:error, :invalid_discovery_method}
    end
  end

  defp discover_from_rss(%SourceSite{} = source_site) do
    rss_url = source_site.rss_url || source_site.url

    with {:ok, feed_xml, etag, last_modified} <- fetch_feed(rss_url, source_site),
         {:ok, entries} <- RssParser.parse(feed_xml, source_site.url) do
      Langler.Content.upsert_discovered_articles(source_site.id, entries)
      Langler.Content.mark_source_checked(source_site, etag, last_modified)
      {:ok, length(entries)}
    else
      {:error, :not_modified} ->
        Langler.Content.mark_source_checked(source_site)
        {:ok, 0}

      {:error, reason} ->
        Langler.Content.mark_source_error(source_site, inspect(reason))
        {:error, reason}
    end
  end

  defp discover_from_scraping(%SourceSite{} = source_site) do
    with {:ok, html} <- fetch_html(source_site.url),
         {:ok, entries} <- WebScraper.scrape(html, source_site.url, source_site.scraping_config || %{}),
         {:ok, _} <- Langler.Content.upsert_discovered_articles(source_site.id, entries) do
      Langler.Content.mark_source_checked(source_site)
      {:ok, length(entries)}
    else
      {:error, reason} ->
        Langler.Content.mark_source_error(source_site, inspect(reason))
        {:error, reason}
    end
  end

  defp discover_hybrid(%SourceSite{} = source_site) do
    # Try RSS first, fallback to scraping
    case discover_from_rss(source_site) do
      {:ok, count} when count > 0 -> {:ok, count}
      _ -> discover_from_scraping(source_site)
    end
  end

  defp fetch_feed(url, %SourceSite{} = source_site) do
    headers = build_conditional_headers(source_site)

    case Req.get(
           url: url,
           headers: headers,
           redirect: :follow,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 304}} ->
        {:error, :not_modified}

      {:ok, %{status: status, body: body, headers: response_headers}}
      when status in 200..299 ->
        etag = get_header(response_headers, "etag")
        last_modified = get_header(response_headers, "last-modified")
        {:ok, body, etag, last_modified}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_html(url) do
    case Req.get(
           url: url,
           headers: [{"user-agent", "LanglerBot/0.1"}],
           redirect: :follow,
           receive_timeout: 10_000
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_conditional_headers(%SourceSite{} = source_site) do
    headers = [{"user-agent", "LanglerBot/0.1"}]

    headers =
      if source_site.etag do
        [{"if-none-match", source_site.etag} | headers]
      else
        headers
      end

    if source_site.last_modified do
      [{"if-modified-since", source_site.last_modified} | headers]
    else
      headers
    end
  end

  defp get_header(headers, key) when is_map(headers) do
    # Req returns headers as a map
    case Map.fetch(headers, key) do
      {:ok, value} -> List.first(value) || value
      :error -> nil
    end
  end

  defp get_header(headers, key) when is_list(headers) do
    # Fallback for list format
    case List.keyfind(headers, key, 0, :error) do
      {^key, value} -> value
      :error -> nil
    end
  end
end

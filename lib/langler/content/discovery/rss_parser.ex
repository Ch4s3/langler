defmodule Langler.Content.Discovery.RssParser do
  @moduledoc """
  Parses RSS feeds to extract article URLs, titles, and metadata.

  Uses Floki for XML parsing and provides normalized article data
  for the discovery pipeline.
  """

  alias Langler.Content.Discovery.UrlNormalizer

  require Logger

  @doc """
  Parses RSS/Atom feed XML and returns a list of article entries.
  Returns `{:ok, entries}` where entries is a list of maps with :url, :title, :summary, :published_at.
  """
  @spec parse(String.t(), String.t()) :: {:ok, list(map())} | {:error, term()}
  def parse(feed_xml, base_url) do
    case Floki.parse_document(feed_xml) do
      {:ok, document} ->
        # Try RSS 2.0 format first
        entries =
          document
          |> Floki.find("item")
          |> Enum.map(&parse_rss_item(&1, base_url))

        # If no RSS items found, try Atom format
        entries =
          if Enum.empty?(entries) do
            document
            |> Floki.find("entry")
            |> Enum.map(&parse_atom_entry(&1, base_url))
          else
            entries
          end

        {:ok, Enum.filter(entries, &(!is_nil(&1)))}

      {:error, reason} ->
        Logger.warning("RSS parsing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_rss_item(item, base_url) do
    link = extract_text(item, "link")
    title = extract_text(item, "title")
    description = extract_text(item, "description")
    pub_date = extract_text(item, "pubDate")

    case normalize_link(link, base_url) do
      {:ok, normalized_url} ->
        %{
          url: normalized_url,
          title: clean_text(title),
          summary: clean_text(description),
          published_at: parse_date(pub_date)
        }

      _ ->
        nil
    end
  end

  defp parse_atom_entry(entry, base_url) do
    # Atom feeds use <link href="..."> or <link>text</link>
    link =
      case Floki.find(entry, "link") do
        [] ->
          nil

        [link_elem | _] ->
          Floki.attribute(link_elem, "href") |> List.first() || Floki.text(link_elem)
      end

    title = extract_text(entry, "title")
    summary = extract_text(entry, "summary") || extract_text(entry, "content")
    updated = extract_text(entry, "updated") || extract_text(entry, "published")

    case normalize_link(link, base_url) do
      {:ok, normalized_url} ->
        %{
          url: normalized_url,
          title: clean_text(title),
          summary: clean_text(summary),
          published_at: parse_date(updated)
        }

      _ ->
        nil
    end
  end

  defp extract_text(element, selector) do
    case Floki.find(element, selector) do
      [] -> nil
      [found | _] -> extract_text_from_element(found)
    end
  end

  defp extract_text_from_element(found) do
    raw_html = Floki.raw_html(found)

    text =
      if raw_html do
        extract_text_from_raw_html(raw_html)
      else
        Floki.text(found)
      end

    if text, do: String.trim(text), else: nil
  end

  defp extract_text_from_raw_html(raw_html) do
    # Remove CDATA wrapper if present: <![CDATA[...]]>
    cleaned = String.replace(raw_html, ~r/<!\[CDATA\[(.*?)\]\]>/s, "\\1")

    if String.contains?(cleaned, "<") do
      parse_html_fragment(cleaned)
    else
      cleaned
    end
  end

  defp parse_html_fragment(cleaned) do
    case Floki.parse_fragment(cleaned) do
      {:ok, doc} -> Floki.text(doc)
      _ -> cleaned
    end
  end

  defp normalize_link(nil, _base_url), do: {:error, :no_link}

  defp normalize_link(link, base_url), do: UrlNormalizer.normalize(link, base_url)

  defp clean_text(nil), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # Try ISO8601 format first
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end
end

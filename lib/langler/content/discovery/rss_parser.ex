defmodule Langler.Content.Discovery.RssParser do
  @moduledoc """
  Parses RSS feeds to extract article URLs, titles, and metadata.
  Uses Floki for XML parsing.
  """

  require Logger

  @doc """
  Parses RSS/Atom feed XML and returns a list of article entries.
  Returns `{:ok, entries}` where entries is a list of maps with :url, :title, :summary, :published_at.
  """
  @spec parse(String.t(), String.t()) :: {:ok, list(map())} | {:error, term()}
  def parse(feed_xml, base_url) do
    with {:ok, document} <- Floki.parse_document(feed_xml) do
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
    else
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

    with {:ok, normalized_url} <- normalize_link(link, base_url) do
      %{
        url: normalized_url,
        title: clean_text(title),
        summary: clean_text(description),
        published_at: parse_date(pub_date)
      }
    else
      _ -> nil
    end
  end

  defp parse_atom_entry(entry, base_url) do
    # Atom feeds use <link href="..."> or <link>text</link>
    link =
      case Floki.find(entry, "link") do
        [] -> nil
        [link_elem | _] -> Floki.attribute(link_elem, "href") |> List.first() || Floki.text(link_elem)
      end

    title = extract_text(entry, "title")
    summary = extract_text(entry, "summary") || extract_text(entry, "content")
    updated = extract_text(entry, "updated") || extract_text(entry, "published")

    with {:ok, normalized_url} <- normalize_link(link, base_url) do
      %{
        url: normalized_url,
        title: clean_text(title),
        summary: clean_text(summary),
        published_at: parse_date(updated)
      }
    else
      _ -> nil
    end
  end

  defp extract_text(element, selector) do
    case Floki.find(element, selector) do
      [] -> nil
      [found | _] ->
        # Get raw HTML/text content to handle CDATA
        raw_html = Floki.raw_html(found)

        # Extract text, handling CDATA sections
        text =
          if raw_html do
            # Remove CDATA wrapper if present: <![CDATA[...]]>
            cleaned = String.replace(raw_html, ~r/<!\[CDATA\[(.*?)\]\]>/s, "\\1")

            # If there are HTML tags, parse and extract text
            # Otherwise, use the cleaned text directly
            if String.contains?(cleaned, "<") do
              case Floki.parse_fragment(cleaned) do
                {:ok, doc} -> Floki.text(doc)
                _ -> cleaned
              end
            else
              cleaned
            end
          else
            Floki.text(found)
          end

        # Clean up whitespace
        if text, do: String.trim(text), else: nil
    end
  end

  defp normalize_link(nil, _base_url), do: {:error, :no_link}
  defp normalize_link(link, base_url), do: Langler.Content.Discovery.UrlNormalizer.normalize(link, base_url)

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

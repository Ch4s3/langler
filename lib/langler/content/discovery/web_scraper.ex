defmodule Langler.Content.Discovery.WebScraper do
  @moduledoc """
  Scrapes article links from websites using configured selectors.
  """

  require Logger
  alias Langler.Content.Discovery.UrlNormalizer

  @doc """
  Scrapes article links from HTML using scraping config.
  Config should contain:
  - "list_selector": CSS selector for the container of article links
  - "link_selector": CSS selector for the link element (defaults to "a[href]")
  - "allow_patterns": List of regex patterns to allow
  - "deny_patterns": List of regex patterns to deny
  """
  @spec scrape(String.t(), String.t(), map()) :: {:ok, list(map())} | {:error, term()}
  def scrape(html, base_url, config \\ %{}) do
    with {:ok, document} <- Floki.parse_document(html) do
      list_selector = Map.get(config, "list_selector") || "body"
      link_selector = Map.get(config, "link_selector") || "a[href]"

      entries =
        document
        |> Floki.find(list_selector)
        |> Enum.flat_map(fn container ->
          Floki.find(container, link_selector)
          |> Enum.map(&extract_link(&1, base_url, config))
        end)
        |> Enum.filter(&(!is_nil(&1)))
        |> Enum.uniq_by(& &1.url)

      {:ok, entries}
    else
      {:error, reason} ->
        Logger.warning("Web scraping failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_link(link_element, base_url, config) do
    href = Floki.attribute(link_element, "href") |> List.first()
    title = Floki.text(link_element) |> String.trim()

    with {:ok, normalized_url} <- UrlNormalizer.normalize(href, base_url),
         true <- UrlNormalizer.matches_patterns?(normalized_url, config) do
      %{
        url: normalized_url,
        title: if(title != "", do: title, else: nil),
        summary: nil,
        published_at: nil
      }
    else
      _ -> nil
    end
  end
end

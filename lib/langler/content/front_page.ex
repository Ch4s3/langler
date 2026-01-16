defmodule Langler.Content.FrontPage do
  @moduledoc """
  Fetches random article links from curated publisher front pages.
  """

  require Logger

  @default_headers [
    {"user-agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0 Safari/537.36"}
  ]

  @doc """
  Attempts to fetch a random article URL from the given source config.

  The source map must include:

    * `:front_page` - the URL to scrape
    * `:article_pattern` - regex to validate article URLs
    * `:label` - human readable name, used for logging
  """
  def random_article(%{front_page: front_page} = source) do
    with {:ok, body} <- fetch_front_page(front_page),
         {:ok, document} <- Floki.parse_document(body),
         links <- extract_links(document, source),
         false <- Enum.empty?(links) do
      {:ok, Enum.random(links)}
    else
      true -> {:error, :no_links}
      {:error, _} = error -> error
    end
  end

  defp fetch_front_page(url) do
    case Req.get(url: url, headers: @default_headers, redirect: true, cache: false) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Front page fetch failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_links(document, %{front_page: front_page} = source) do
    document
    |> Floki.find(source[:link_selector] || "a[href]")
    |> Enum.map(&Floki.attribute(&1, "href"))
    |> Enum.flat_map(& &1)
    |> Enum.map(&normalize_href(&1, front_page))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Regex.match?(source.article_pattern, &1))
    |> Enum.uniq()
  end

  defp normalize_href(nil, _front_page), do: nil

  defp normalize_href("mailto:" <> _, _front_page), do: nil
  defp normalize_href("javascript:" <> _, _front_page), do: nil

  defp normalize_href("//" <> rest, front_page) do
    %URI{scheme: scheme} = URI.parse(front_page)
    "#{scheme}://#{rest}"
  end

  defp normalize_href("http" <> _ = href, _front_page), do: href

  defp normalize_href(path, front_page) do
    base = URI.parse(front_page)

    case URI.merge(base, path) do
      %URI{host: host} = uri when is_binary(host) ->
        URI.to_string(uri)

      _ ->
        nil
    end
  rescue
    ArgumentError ->
      nil
  end
end

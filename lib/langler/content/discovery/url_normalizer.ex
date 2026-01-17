defmodule Langler.Content.Discovery.UrlNormalizer do
  @moduledoc """
  Normalizes URLs for article discovery.

  Strips tracking parameters, normalizes scheme (http/https), and resolves
  relative URLs to ensure consistent URL handling across the discovery system.
  """

  @doc """
  Normalizes a URL by:
  - Validating scheme (http/https)
  - Resolving relative URLs against a base URL
  - Stripping common tracking parameters
  - Normalizing the URL string
  """
  @spec normalize(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def normalize(url, base_url \\ nil) do
    with {:ok, uri} <- parse_url(url, base_url),
         {:ok, cleaned_uri} <- strip_tracking_params(uri),
         normalized <- URI.to_string(cleaned_uri) do
      {:ok, normalized}
    end
  end

  @doc """
  Checks if a URL matches allowed/denied patterns from scraping config.
  """
  @spec matches_patterns?(String.t(), map()) :: boolean()
  def matches_patterns?(url, config) do
    allow_patterns = Map.get(config, "allow_patterns", [])
    deny_patterns = Map.get(config, "deny_patterns", [])

    allowed? =
      if Enum.empty?(allow_patterns) do
        true
      else
        Enum.any?(allow_patterns, fn pattern ->
          Regex.match?(~r/#{pattern}/i, url)
        end)
      end

    denied? =
      Enum.any?(deny_patterns, fn pattern ->
        Regex.match?(~r/#{pattern}/i, url)
      end)

    allowed? and not denied?
  end

  defp parse_url(url, nil) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme} = uri} when scheme in ["http", "https"] ->
        {:ok, uri}

      {:ok, _} ->
        {:error, :invalid_scheme}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_url(url, base_url) when is_binary(url) and is_binary(base_url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme} = uri} when scheme in ["http", "https"] ->
        {:ok, uri}

      {:ok, %URI{scheme: nil} = relative_uri} ->
        # Resolve relative URL
        base_uri = URI.parse(base_url)

        resolved =
          relative_uri
          |> Map.put(:scheme, base_uri.scheme)
          |> Map.put(:host, base_uri.host)
          |> Map.put(:port, base_uri.port)

        {:ok, resolved}

      {:ok, _} ->
        {:error, :invalid_scheme}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_url(_, _), do: {:error, :invalid_url}

  defp strip_tracking_params(%URI{} = uri) do
    # Common tracking parameters to remove
    tracking_params = [
      "utm_source",
      "utm_medium",
      "utm_campaign",
      "utm_term",
      "utm_content",
      "fbclid",
      "gclid",
      "ref",
      "source"
    ]

    query_params =
      if uri.query do
        uri.query
        |> URI.decode_query()
        |> Enum.reject(fn {key, _value} ->
          key in tracking_params
        end)
        |> URI.encode_query()
      else
        ""
      end

    {:ok, %{uri | query: if(query_params == "", do: nil, else: query_params)}}
  end
end

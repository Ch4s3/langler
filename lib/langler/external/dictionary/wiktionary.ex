defmodule Langler.External.Dictionary.Wiktionary do
  @moduledoc """
  Minimal Wiktionary HTML scraper for definitions.
  """

  @definition_selector "#mw-content-text .mw-parser-output > ol li"
  @header_selector "h1#firstHeading"

  alias Langler.External.Dictionary

  @spec lookup(String.t(), String.t()) :: {:ok, Dictionary.entry()} | {:error, term()}
  def lookup(term, language) do
    with {:ok, body, url} <- fetch(term) do
      parse(body, term, language, url)
    end
  end

  defp fetch(term) do
    config = Application.get_env(:langler, __MODULE__, [])
    base_url = Keyword.get(config, :base_url, "https://en.wiktionary.org/wiki")

    url =
      [base_url, URI.encode(term)]
      |> Enum.join("/")

    case Req.get(url: url, headers: default_headers(), retry: false) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body, url}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(body, term, language, url) do
    with {:ok, doc} <- Floki.parse_document(body) do
      defs =
        doc
        |> Floki.find(@definition_selector)
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.take(3)

      lemma =
        doc
        |> Floki.find(@header_selector)
        |> Floki.text()
        |> String.trim()
        |> fallback(term)

      part_of_speech =
        doc
        |> Floki.find("#mw-content-text .mw-headline")
        |> Enum.map(&Floki.text/1)
        |> Enum.find(fn heading ->
          heading in ["Noun", "Verb", "Adjective", "Adverb"]
        end)

      entry = %{
        word: term,
        lemma: lemma,
        language: language,
        part_of_speech: part_of_speech,
        pronunciation: nil,
        definitions: defs,
        source_url: url,
        translation: nil
      }

      if defs == [] do
        {:error, :not_found}
      else
        {:ok, entry}
      end
    end
  end

  defp default_headers do
    [
      {"user-agent", "LanglerBot/0.1 (+https://langler.local)"}
    ]
  end

  defp fallback(value, term) when value in [nil, ""], do: term
  defp fallback(value, _term), do: value
end

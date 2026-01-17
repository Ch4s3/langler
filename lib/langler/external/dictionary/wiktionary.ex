defmodule Langler.External.Dictionary.Wiktionary do
  @moduledoc """
  Minimal Wiktionary HTML scraper for extracting word definitions.

  Parses Wiktionary pages to extract definitions, pronunciations, and
  part-of-speech information for language learning purposes.
  """

  @header_selector "h1#firstHeading"

  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.Cache

  @spec lookup(String.t(), String.t()) :: {:ok, Dictionary.entry()} | {:error, term()}
  def lookup(term, language) do
    normalized_language = String.downcase(language || "")
    cache_key = {normalized_language, String.downcase(term)}
    table = cache_table()

    Cache.get_or_store(table, cache_key, [ttl: ttl()], fn ->
      with {:ok, body, url} <- fetch_with_fallback(term, normalized_language) do
        parse(body, term, normalized_language, url)
      end
    end)
  end

  defp fetch_with_fallback(term, language) do
    term
    |> candidate_terms()
    |> Enum.reduce_while({:error, :not_found}, fn candidate, _acc ->
      case fetch(candidate, language) do
        {:ok, body, url} ->
          {:halt, {:ok, body, url}}

        {:error, {:http_error, 404}} ->
          {:cont, {:error, :not_found}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp fetch(term, language) do
    config = Application.get_env(:langler, __MODULE__, [])
    base_url = Keyword.get(config, :base_url, "https://en.wiktionary.org/wiki")

    url =
      [base_url, URI.encode(term)]
      |> Enum.join("/")
      |> with_language_anchor(language)

    case Req.get([url: url, headers: default_headers(), retry: false] ++ req_options()) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body, url}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @dialyzer {:nowarn_function, candidate_terms: 1}
  defp candidate_terms(term) do
    lower = String.downcase(term || "")

    [term, lower]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.dedup()
  end

  defp parse(body, term, language, url) do
    with {:ok, doc} <- Floki.parse_document(body) do
      defs =
        doc
        |> extract_language_definitions(language)
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

  defp cache_table do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :cache_table, :wiktionary_cache)
  end

  defp ttl do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :ttl, :timer.hours(6))
  end

  defp req_options do
    config = Application.get_env(:langler, __MODULE__, [])
    Keyword.get(config, :req_options, [])
  end

  defp default_headers do
    [
      {"user-agent", "LanglerBot/0.1 (+https://langler.local)"}
    ]
  end

  defp fallback(value, term) when value in [nil, ""], do: term
  defp fallback(value, _term), do: value

  defp extract_language_definitions(doc, language) do
    anchor = language_anchor(language)

    doc
    |> Floki.find("#mw-content-text .mw-parser-output")
    |> List.first()
    |> case do
      nil ->
        []

      {_tag, _attrs, children} ->
        children
        |> take_language_section(anchor)
        |> Enum.flat_map(&Floki.find(&1, "ol li"))
        |> Enum.map(&Floki.text/1)
        |> Enum.map(&String.replace(&1, ~r/\[\d+\]/, ""))
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp take_language_section(children, nil), do: children

  defp take_language_section(children, anchor) do
    {found, acc} =
      Enum.reduce_while(children, {false, []}, fn node, {found, acc} ->
        cond do
          language_heading?(node, anchor) ->
            {:cont, {true, []}}

          found && heading?(node) ->
            {:halt, {found, acc}}

          found ->
            {:cont, {found, [node | acc]}}

          true ->
            {:cont, {found, acc}}
        end
      end)

    case {found, acc} do
      {false, _} -> children
      {_found, acc} -> Enum.reverse(acc)
    end
  end

  defp language_heading?({"h2", _attrs, children}, anchor) do
    Enum.any?(children, fn
      {"span", span_attrs, _} ->
        id =
          Enum.find_value(span_attrs, fn
            {"id", value} -> value
            _ -> nil
          end)

        class =
          Enum.find_value(span_attrs, fn
            {"class", value} -> value
            _ -> nil
          end)

        id == anchor && String.contains?(class || "", "mw-headline")

      _ ->
        false
    end)
  end

  defp language_heading?(_, _), do: false

  defp heading?({"h2", _, _}), do: true
  defp heading?(_), do: false

  defp with_language_anchor(url, ""), do: url

  defp with_language_anchor(url, language) do
    anchor =
      language
      |> language_anchor()
      |> case do
        nil -> nil
        value -> "##{value}"
      end

    if anchor, do: url <> anchor, else: url
  end

  defp language_anchor("spanish"), do: "Spanish"
  defp language_anchor("french"), do: "French"
  defp language_anchor("english"), do: "English"
  defp language_anchor("german"), do: "German"
  defp language_anchor("italian"), do: "Italian"
  defp language_anchor("portuguese"), do: "Portuguese"
  defp language_anchor(_), do: nil
end

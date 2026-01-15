defmodule Langler.External.Dictionary do
  @moduledoc """
  Dictionary lookups combining Wiktionary definitions, Google Translate fallback,
  and LanguageTool for lemma/part-of-speech analysis.
  """

  alias Langler.External.Dictionary.{Google, LanguageTool, Wiktionary, Cache}

  @entry_cache_version 2

  @type entry :: %{
          word: String.t(),
          lemma: String.t() | nil,
          language: String.t(),
          part_of_speech: String.t() | nil,
          pronunciation: String.t() | nil,
          definitions: [String.t()],
          translation: String.t() | nil,
          source_url: String.t() | nil
        }

  @doc """
  Fetches dictionary information for a given term using Google Translate.

  Always returns an entry with translation from Google Translate.
  """
  @spec lookup(String.t(), keyword()) :: {:ok, entry()}
  def lookup(term, opts \\ []) when is_binary(term) do
    language = opts[:language] || "spanish"
    target = opts[:target] || "en"

    entry_cache = cache_table(:entry)
    entry_key = {@entry_cache_version, String.downcase(language), String.downcase(term)}

    case Cache.get(entry_cache, entry_key) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        google_data = fetch_google_data(term, language, target)

        wiktionary_entry =
          case Wiktionary.lookup(term, language) do
            {:ok, entry} -> entry
            {:error, _} -> nil
          end

        {part_of_speech, lemma_candidate} =
          case LanguageTool.analyze(term, language: language) do
            {:ok, %{part_of_speech: pos, lemma: lem}} ->
              {pos, lem}

            {:error, _} ->
              {nil, nil}
          end

        lemma = normalize_lemma(lemma_candidate, term)
        lemma_query = lemma_candidate && String.trim(lemma_candidate)

        lemma_google_data =
          if needs_lemma_lookup?(google_data, lemma_query, term) do
            fetch_google_data(lemma_query, language, target)
          else
            nil
          end

        definitions =
          cond do
            google_data.definitions != [] ->
              google_data.definitions

            lemma_google_data && lemma_google_data.definitions != [] ->
              lemma_google_data.definitions

            wiktionary_entry && wiktionary_entry.definitions != [] ->
              wiktionary_entry.definitions

            google_data.translation ->
              [google_data.translation]

            lemma_google_data && lemma_google_data.translation ->
              [lemma_google_data.translation]

            true ->
              []
          end

        entry = %{
          word: term,
          lemma: lemma,
          language: language,
          part_of_speech:
            part_of_speech ||
              (wiktionary_entry && wiktionary_entry.part_of_speech),
          pronunciation: wiktionary_entry && wiktionary_entry.pronunciation,
          definitions: definitions,
          translation:
            google_data.translation || (lemma_google_data && lemma_google_data.translation),
          source_url: wiktionary_entry && wiktionary_entry.source_url
        }

        Cache.put(entry_cache, entry_key, entry, ttl: ttl(:entry))
        {:ok, entry}
    end
  end

  defp capitalize_word(term) do
    # Capitalize first letter while preserving the rest
    case String.split_at(term, 1) do
      {"", _} -> term
      {first, rest} -> String.upcase(first) <> rest
    end
  end

  defp normalize_lemma(nil, term), do: capitalize_word(term)
  defp normalize_lemma("", term), do: capitalize_word(term)
  defp normalize_lemma(lemma, _term), do: capitalize_word(lemma)

  defp cache_table(:entry), do: :dictionary_entry_cache

  defp ttl(:entry), do: :timer.hours(12)

  defp fetch_google_data(nil, _language, _target), do: %{translation: nil, definitions: []}

  defp fetch_google_data(term, language, target) do
    case Google.translate(term, from: language, to: target) do
      {:ok, data} -> data
      {:error, _} -> %{translation: nil, definitions: []}
    end
  end

  defp needs_lemma_lookup?(google_data, lemma_query, term) do
    google_data.definitions == [] and
      is_binary(lemma_query) and lemma_query != "" and
      String.downcase(lemma_query) != String.downcase(term || "")
  end
end

defmodule Langler.External.Dictionary do
  @moduledoc """
  Dictionary lookup service combining multiple data sources.

  Integrates Wiktionary definitions, Google Translate fallback, and LanguageTool
  for lemma/part-of-speech analysis to provide comprehensive dictionary entries.
  """

  alias Langler.External.Dictionary.{Cache, Google, LanguageTool, Wiktionary}

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
        if stale_entry?(cached) do
          {:ok, fetch_and_cache_entry(term, language, target, entry_cache, entry_key)}
        else
          {:ok, cached}
        end

      :miss ->
        {:ok, fetch_and_cache_entry(term, language, target, entry_cache, entry_key)}
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

  defp fetch_and_cache_entry(term, language, target, cache, key) do
    sources = fetch_all_sources(term, language, target)
    entry = build_entry(term, language, sources)
    Cache.put(cache, key, entry, ttl: ttl(:entry))
    entry
  end

  defp stale_entry?(entry) do
    definitions_missing = is_nil(entry.definitions) || entry.definitions == []
    translation_missing = is_nil(entry.translation) || entry.translation == ""
    definitions_missing && translation_missing
  end

  defp fetch_google_data(nil, _language, _target), do: %{translation: nil, definitions: []}

  defp fetch_google_data(term, language, target) do
    case Google.translate(term, from: language, to: target) do
      {:ok, data} -> data
      {:error, _} -> %{translation: nil, definitions: []}
    end
  end

  defp fetch_all_sources(term, language, target) do
    google_data = fetch_google_data(term, language, target)

    wiktionary_entry =
      case Wiktionary.lookup(term, language) do
        {:ok, entry} -> entry
        {:error, _} -> nil
      end

    {part_of_speech, lemma_candidate} = fetch_language_tool_data(term, language)
    lemma = normalize_lemma(lemma_candidate, term)
    lemma_query = lemma_candidate && String.trim(lemma_candidate)

    lemma_google_data =
      if needs_lemma_lookup?(google_data, lemma_query, term) do
        fetch_google_data(lemma_query, language, target)
      else
        nil
      end

    %{
      google_data: google_data,
      lemma_google_data: lemma_google_data,
      wiktionary_entry: wiktionary_entry,
      part_of_speech: part_of_speech,
      lemma: lemma
    }
  end

  defp fetch_language_tool_data(term, language) do
    case LanguageTool.analyze(term, language: language) do
      {:ok, %{part_of_speech: pos, lemma: lem}} ->
        {pos, lem}

      {:error, _} ->
        {nil, nil}
    end
  end

  defp build_entry(term, language, sources) do
    definitions = build_definitions(sources)
    translation = get_translation(sources)

    %{
      word: term,
      lemma: sources.lemma,
      language: language,
      part_of_speech: get_part_of_speech(sources),
      pronunciation: get_pronunciation(sources),
      definitions: definitions,
      translation: translation,
      source_url: get_source_url(sources)
    }
  end

  defp build_definitions(sources) do
    build_definitions_from_sources(sources) || build_definitions_from_translations(sources) || []
  end

  defp build_definitions_from_sources(sources) do
    cond do
      sources.google_data.definitions != [] ->
        sources.google_data.definitions

      has_lemma_definitions?(sources) ->
        sources.lemma_google_data.definitions

      has_wiktionary_definitions?(sources) ->
        sources.wiktionary_entry.definitions

      true ->
        nil
    end
  end

  defp build_definitions_from_translations(sources) do
    cond do
      sources.google_data.translation ->
        [sources.google_data.translation]

      has_lemma_translation?(sources) ->
        [sources.lemma_google_data.translation]

      true ->
        nil
    end
  end

  defp has_lemma_definitions?(sources) do
    sources.lemma_google_data && sources.lemma_google_data.definitions != []
  end

  defp has_wiktionary_definitions?(sources) do
    sources.wiktionary_entry && sources.wiktionary_entry.definitions != []
  end

  defp has_lemma_translation?(sources) do
    sources.lemma_google_data && sources.lemma_google_data.translation
  end

  defp get_translation(sources) do
    sources.google_data.translation ||
      (sources.lemma_google_data && sources.lemma_google_data.translation)
  end

  defp get_part_of_speech(sources) do
    sources.part_of_speech ||
      (sources.wiktionary_entry && sources.wiktionary_entry.part_of_speech)
  end

  defp get_pronunciation(sources) do
    sources.wiktionary_entry && sources.wiktionary_entry.pronunciation
  end

  defp get_source_url(sources) do
    sources.wiktionary_entry && sources.wiktionary_entry.source_url
  end

  @dialyzer {:nowarn_function, needs_lemma_lookup?: 3}
  defp needs_lemma_lookup?(google_data, lemma_query, term) do
    google_data.definitions == [] and
      is_binary(lemma_query) and lemma_query != "" and
      String.downcase(lemma_query) != String.downcase(term || "")
  end
end

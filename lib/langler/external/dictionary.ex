defmodule Langler.External.Dictionary do
  @moduledoc """
  Dictionary lookup service combining multiple data sources.

  Integrates Wiktionary definitions, definition providers (Google Translate or LLM),
  and LanguageTool for lemma/part-of-speech analysis to provide comprehensive
  dictionary entries.
  """

  alias Langler.External.Dictionary.{Cache, DefinitionResolver, LanguageTool, Wiktionary}

  @entry_cache_version 3

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
  Fetches dictionary information for a given term.

  Uses the configured definition provider (Google Translate or LLM) based on
  user configuration, with automatic fallback from Google Translate to LLM
  when Google Translate is not configured.

  ## Options
    - `:language` - Source language (default: "spanish")
    - `:target` - Target language for translation (default: "en")
    - `:api_key` - API key for Google Translate (optional, overrides user config)
    - `:user_id` - User ID for provider resolution (optional but recommended)
  """
  @spec lookup(String.t(), keyword()) :: {:ok, entry()} | {:error, term()}
  def lookup(term, opts \\ []) when is_binary(term) do
    language = opts[:language] || "spanish"
    target = opts[:target] || "en"
    user_id = opts[:user_id]

    entry_cache = cache_table(:entry)
    entry_key = {@entry_cache_version, String.downcase(language), String.downcase(term)}

    case Cache.get(entry_cache, entry_key) do
      {:ok, cached} ->
        if stale_entry?(cached) do
          fetch_and_cache_entry(term, language, target, opts, entry_cache, entry_key, user_id)
        else
          {:ok, cached}
        end

      :miss ->
        fetch_and_cache_entry(term, language, target, opts, entry_cache, entry_key, user_id)
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

  defp fetch_and_cache_entry(term, language, target, opts, cache, key, user_id) do
    case fetch_all_sources(term, language, target, opts, user_id) do
      {:ok, sources} ->
        entry = build_entry(term, language, sources)
        Cache.put(cache, key, entry, ttl: ttl(:entry))
        {:ok, entry}

      {:error, _reason} = error ->
        error
    end
  end

  defp stale_entry?(entry) do
    definitions_missing = is_nil(entry.definitions) || entry.definitions == []
    translation_missing = is_nil(entry.translation) || entry.translation == ""
    definitions_missing && translation_missing
  end

  defp fetch_definition_data(nil, _language, _target, _opts, _user_id),
    do: %{translation: nil, definitions: []}

  defp fetch_definition_data(term, language, target, opts, user_id) do
    resolver_opts = [
      language: language,
      target: target,
      api_key: opts[:api_key],
      user_id: user_id
    ]

    case DefinitionResolver.get_definition(term, resolver_opts) do
      {:ok, data} -> data
      {:error, :no_provider_available} -> {:error, :no_provider_available}
      {:error, _} -> %{translation: nil, definitions: []}
    end
  end

  defp fetch_all_sources(term, language, target, opts, user_id) do
    case fetch_definition_data(term, language, target, opts, user_id) do
      {:error, _reason} = error ->
        error

      definition_data ->
        {:ok,
         fetch_all_sources_with_definition_data(
           term,
           language,
           target,
           opts,
           user_id,
           definition_data
         )}
    end
  end

  defp fetch_all_sources_with_definition_data(
         term,
         language,
         target,
         opts,
         user_id,
         definition_data
       ) do
    wiktionary_entry =
      case Wiktionary.lookup(term, language) do
        {:ok, entry} -> entry
        {:error, _} -> nil
      end

    {part_of_speech, lemma_candidate} = fetch_language_tool_data(term, language)
    lemma = normalize_lemma(lemma_candidate, term)
    lemma_query = lemma_candidate && String.trim(lemma_candidate)

    lemma_definition_data =
      if needs_lemma_lookup?(definition_data, lemma_query, term) do
        case fetch_definition_data(lemma_query, language, target, opts, user_id) do
          {:error, _} -> nil
          data -> data
        end
      else
        nil
      end

    %{
      definition_data: definition_data,
      lemma_definition_data: lemma_definition_data,
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
      sources.definition_data.definitions != [] ->
        sources.definition_data.definitions

      has_lemma_definitions?(sources) ->
        sources.lemma_definition_data.definitions

      has_wiktionary_definitions?(sources) ->
        sources.wiktionary_entry.definitions

      true ->
        nil
    end
  end

  defp build_definitions_from_translations(sources) do
    cond do
      sources.definition_data.translation ->
        [sources.definition_data.translation]

      has_lemma_translation?(sources) ->
        [sources.lemma_definition_data.translation]

      true ->
        nil
    end
  end

  defp has_lemma_definitions?(sources) do
    sources.lemma_definition_data && sources.lemma_definition_data.definitions != []
  end

  defp has_wiktionary_definitions?(sources) do
    sources.wiktionary_entry && sources.wiktionary_entry.definitions != []
  end

  defp has_lemma_translation?(sources) do
    sources.lemma_definition_data && sources.lemma_definition_data.translation
  end

  defp get_translation(sources) do
    sources.definition_data.translation ||
      (sources.lemma_definition_data && sources.lemma_definition_data.translation)
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
  defp needs_lemma_lookup?(definition_data, lemma_query, term) do
    definition_data.definitions == [] and
      is_binary(lemma_query) and lemma_query != "" and
      String.downcase(lemma_query) != String.downcase(term || "")
  end
end

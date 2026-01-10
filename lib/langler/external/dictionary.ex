defmodule Langler.External.Dictionary do
  @moduledoc """
  Aggregates dictionary lookups across providers (Wiktionary + Google Translate fallback).
  """

  alias Langler.External.Dictionary.{Google, Wiktionary}

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

  Always returns an entry, falling back to synthesized data if all providers fail.
  """
  @spec lookup(String.t(), keyword()) :: {:ok, entry()}
  def lookup(term, opts \\ []) when is_binary(term) do
    language = opts[:language] || "spanish"
    target = opts[:target] || "en"

    entry =
      case Wiktionary.lookup(term, language) do
        {:ok, entry} ->
          entry

        {:error, _reason} ->
          fallback_entry(term, language)
      end

    translation =
      case Google.translate(term, from: language, to: target) do
        {:ok, translated} -> translated
        {:error, _} -> nil
      end

    {:ok, Map.put(entry, :translation, translation)}
  end

  @doc """
  Returns a basic entry when providers fail.
  """
  @spec fallback_entry(String.t(), String.t()) :: entry()
  def fallback_entry(term, language) do
    %{
      word: term,
      lemma: String.capitalize(term),
      language: language,
      part_of_speech: nil,
      pronunciation: nil,
      definitions: [],
      translation: nil,
      source_url: nil
    }
  end
end

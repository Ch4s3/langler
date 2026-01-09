defmodule Langler.Vocabulary do
  @moduledoc """
  Vocabulary + occurrences domain.
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Vocabulary.{Word, WordOccurrence}

  def normalize_form(nil), do: nil

  def normalize_form(term) when is_binary(term) do
    term
    |> String.normalize(:nfd)
    |> String.downcase()
    |> String.replace(~r/\p{Mn}/u, "")
  end

  def get_word_by_normalized_form(normalized_form, language) do
    Repo.get_by(Word, normalized_form: normalized_form, language: language)
  end

  def get_or_create_word(attrs) do
    normalized =
      attrs
      |> fetch_any([:normalized_form, "normalized_form", :lemma])
      |> normalize_form()

    language = fetch_any(attrs, [:language, "language"])

    case get_word_by_normalized_form(normalized, language) do
      nil ->
        attrs
        |> Enum.into(%{})
        |> Map.put(:normalized_form, normalized)
        |> Map.put(:language, language)
        |> create_word()

      word ->
        {:ok, word}
    end
  end

  defp fetch_any(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when value not in [nil, ""] -> value
        _ -> nil
      end
    end) || raise ArgumentError, "missing required attribute"
  end

  def create_word(attrs \\ %{}) do
    %Word{}
    |> Word.changeset(attrs)
    |> Repo.insert()
  end

  def change_word(%Word{} = word, attrs \\ %{}) do
    Word.changeset(word, attrs)
  end

  def create_occurrence(attrs \\ %{}) do
    %WordOccurrence{}
    |> WordOccurrence.changeset(attrs)
    |> Repo.insert()
  end

  def list_occurrences_for_sentence(sentence_id) do
    WordOccurrence
    |> where(sentence_id: ^sentence_id)
    |> order_by([o], asc: o.position)
    |> Repo.all()
    |> Repo.preload(:word)
  end
end

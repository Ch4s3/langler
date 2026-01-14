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

  def get_word(id), do: Repo.get(Word, id)
  def get_word!(id), do: Repo.get!(Word, id)

  def get_word_by_normalized_form(normalized_form, language) do
    Repo.get_by(Word, normalized_form: normalized_form, language: language)
  end

  def get_or_create_word(attrs) do
    normalized =
      attrs
      |> fetch_any([:normalized_form, "normalized_form", :lemma])
      |> normalize_form()

    language = fetch_any(attrs, [:language, "language"])
    definitions = fetch_optional(attrs, [:definitions, "definitions"]) || []

    case get_word_by_normalized_form(normalized, language) do
      nil ->
        attrs
        |> Enum.into(%{})
        |> Map.put(:normalized_form, normalized)
        |> Map.put(:language, language)
        |> Map.put_new(:definitions, definitions)
        |> create_word()

      word ->
        maybe_update_definitions(word, definitions)
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

  def update_word_definitions(%Word{} = word, definitions) when is_list(definitions) do
    word
    |> Word.changeset(%{definitions: definitions})
    |> Repo.update()
  end

  def update_word_conjugations(%Word{} = word, conjugations) when is_map(conjugations) do
    word
    |> Word.changeset(%{conjugations: conjugations})
    |> Repo.update()
  end

  defp maybe_update_definitions(word, definitions)
       when definitions in [nil, []] or definitions == word.definitions do
    {:ok, word}
  end

  defp maybe_update_definitions(%Word{} = word, definitions) do
    word
    |> Word.changeset(%{definitions: definitions})
    |> Repo.update()
  end

  defp fetch_optional(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when value not in [nil, ""] -> value
        _ -> nil
      end
    end)
  rescue
    _ -> nil
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

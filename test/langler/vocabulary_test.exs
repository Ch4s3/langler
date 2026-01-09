defmodule Langler.VocabularyTest do
  use Langler.DataCase, async: true

  alias Langler.Vocabulary
  alias Langler.ContentFixtures

  test "normalize_form/1 strips accents and lowercases" do
    assert Vocabulary.normalize_form("Árbol") == "arbol"
  end

  test "get_or_create_word/1 inserts a new word" do
    {:ok, word} =
      Vocabulary.get_or_create_word(%{
        lemma: "hola",
        language: "spanish",
        part_of_speech: "interjection"
      })

    assert word.normalized_form == "hola"
  end

  test "create_occurrence/1 stores occurrence" do
    sentence = ContentFixtures.sentence_fixture()

    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "mundo",
        lemma: "mundo",
        language: "spanish",
        part_of_speech: "noun"
      })

    {:ok, occurrence} =
      Vocabulary.create_occurrence(%{
        word_id: word.id,
        sentence_id: sentence.id,
        position: 1,
        context: sentence.content
      })

    assert occurrence.word_id == word.id
    occurrence_id = occurrence.id

    assert [%{id: ^occurrence_id}] = Vocabulary.list_occurrences_for_sentence(sentence.id)
  end
end

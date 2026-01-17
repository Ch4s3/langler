defmodule Langler.VocabularyTest do
  use Langler.DataCase, async: true

  alias Langler.ContentFixtures
  alias Langler.Vocabulary

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

  test "get_word/1 returns word by id" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "test",
        lemma: "test",
        language: "spanish"
      })

    assert Vocabulary.get_word(word.id).id == word.id
  end

  test "get_word/1 returns nil for non-existent id" do
    assert Vocabulary.get_word(-1) == nil
  end

  test "get_word!/1 raises for non-existent id" do
    assert_raise Ecto.NoResultsError, fn ->
      Vocabulary.get_word!(-1)
    end
  end

  test "get_word_by_normalized_form/2 returns word" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "hola",
        lemma: "hola",
        language: "spanish"
      })

    found = Vocabulary.get_word_by_normalized_form("hola", "spanish")
    assert found.id == word.id
  end

  test "get_word_by_normalized_form/2 returns nil when not found" do
    assert Vocabulary.get_word_by_normalized_form("nonexistent", "spanish") == nil
  end

  test "get_or_create_word/1 returns existing word" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "existente",
        lemma: "existente",
        language: "spanish"
      })

    {:ok, found} = Vocabulary.get_or_create_word(%{lemma: "existente", language: "spanish"})
    assert found.id == word.id
  end

  test "get_or_create_word/1 creates word with definitions" do
    {:ok, word} =
      Vocabulary.get_or_create_word(%{
        lemma: "nuevo",
        language: "spanish",
        definitions: ["greeting", "hello"]
      })

    assert word.normalized_form == "nuevo"
    assert word.definitions == ["greeting", "hello"]
  end

  test "update_word_definitions/2 updates definitions" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "test",
        lemma: "test",
        language: "spanish"
      })

    {:ok, updated} = Vocabulary.update_word_definitions(word, ["new", "definitions"])
    assert updated.definitions == ["new", "definitions"]
  end

  test "update_word_conjugations/2 updates conjugations" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "hablar",
        lemma: "hablar",
        language: "spanish"
      })

    conjugations = %{"present" => %{"yo" => "hablo"}}
    {:ok, updated} = Vocabulary.update_word_conjugations(word, conjugations)
    assert updated.conjugations == conjugations
  end

  test "change_word/2 returns changeset" do
    {:ok, word} =
      Vocabulary.create_word(%{
        normalized_form: "test",
        lemma: "test",
        language: "spanish"
      })

    changeset = Vocabulary.change_word(word, %{lemma: "changed"})
    assert changeset.changes.lemma == "changed"
  end

  test "normalize_form/1 handles nil" do
    assert Vocabulary.normalize_form(nil) == nil
  end

  test "normalize_form/1 handles accents" do
    assert Vocabulary.normalize_form("Árbol") == "arbol"
    assert Vocabulary.normalize_form("Niño") == "nino"
  end
end

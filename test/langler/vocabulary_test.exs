defmodule Langler.VocabularyTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures
  import Langler.VocabularyFixtures

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

  describe "deck management" do
    test "get_or_create_default_deck/1 creates default deck when none exists" do
      user = user_fixture()

      assert {:ok, deck} = Vocabulary.get_or_create_default_deck(user.id)
      assert deck.name == "Default"
      assert deck.is_default == true
      assert deck.user_id == user.id
    end

    test "get_or_create_default_deck/1 returns existing default deck" do
      user = user_fixture()

      {:ok, first} = Vocabulary.get_or_create_default_deck(user.id)
      {:ok, second} = Vocabulary.get_or_create_default_deck(user.id)

      assert first.id == second.id
    end

    test "create_deck/2 creates a new deck" do
      user = user_fixture()

      assert {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Spanish Verbs"})
      assert deck.name == "Spanish Verbs"
      assert deck.user_id == user.id
      assert deck.is_default == false
    end

    test "list_decks_for_user/1 returns all user decks" do
      user = user_fixture()

      {:ok, deck1} = Vocabulary.create_deck(user.id, %{name: "Deck 1"})
      {:ok, deck2} = Vocabulary.create_deck(user.id, %{name: "Deck 2"})

      decks = Vocabulary.list_decks_for_user(user.id)

      assert length(decks) == 2
      assert Enum.any?(decks, &(&1.id == deck1.id))
      assert Enum.any?(decks, &(&1.id == deck2.id))
    end

    test "list_decks_for_user/1 preloads words association" do
      user = user_fixture()
      word = word_fixture()

      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test Deck"})
      Vocabulary.add_word_to_deck(deck.id, word.id, user.id)

      decks = Vocabulary.list_decks_for_user(user.id)

      # Should have words preloaded
      found_deck = Enum.find(decks, &(&1.id == deck.id))
      assert found_deck
      assert Ecto.assoc_loaded?(found_deck.words)
    end

    test "get_deck_for_user!/2 returns deck when it belongs to user" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})

      found = Vocabulary.get_deck_for_user!(deck.id, user.id)
      assert found.id == deck.id
    end

    test "get_deck_for_user!/2 raises when deck doesn't belong to user" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user1.id, %{name: "Test"})

      assert_raise Ecto.NoResultsError, fn ->
        Vocabulary.get_deck_for_user!(deck.id, user2.id)
      end
    end

    test "get_deck_for_user/2 returns deck when it belongs to user" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})

      found = Vocabulary.get_deck_for_user(deck.id, user.id)
      assert found.id == deck.id
    end

    test "get_deck_for_user/2 returns nil when deck doesn't belong to user" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user1.id, %{name: "Test"})

      assert Vocabulary.get_deck_for_user(deck.id, user2.id) == nil
    end

    test "update_deck/3 updates deck attributes" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Original"})

      assert {:ok, updated} = Vocabulary.update_deck(deck.id, user.id, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "update_deck/3 prevents unsetting is_default on default deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.get_or_create_default_deck(user.id)

      assert {:ok, updated} =
               Vocabulary.update_deck(deck.id, user.id, %{is_default: false, name: "New Name"})

      assert updated.is_default == true
      assert updated.name == "New Name"
    end

    test "update_deck/3 returns error when deck not found" do
      user = user_fixture()

      assert {:error, :not_found} = Vocabulary.update_deck(999_999, user.id, %{name: "Test"})
    end

    test "delete_deck/2 deletes non-default deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Temp"})

      assert {:ok, _} = Vocabulary.delete_deck(deck.id, user.id)
      assert Vocabulary.get_deck_for_user(deck.id, user.id) == nil
    end

    test "delete_deck/2 prevents deleting default deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.get_or_create_default_deck(user.id)

      assert {:error, :cannot_delete_default} = Vocabulary.delete_deck(deck.id, user.id)
    end

    test "delete_deck/2 returns error when deck not found" do
      user = user_fixture()

      assert {:error, :not_found} = Vocabulary.delete_deck(999_999, user.id)
    end

    test "add_word_to_deck/3 adds word to deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})
      word = word_fixture()

      assert {:ok, deck_word} = Vocabulary.add_word_to_deck(deck.id, word.id, user.id)
      assert deck_word.deck_id == deck.id
      assert deck_word.word_id == word.id
    end

    test "add_word_to_deck/3 returns existing association if already added" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})
      word = word_fixture()

      {:ok, first} = Vocabulary.add_word_to_deck(deck.id, word.id, user.id)
      {:ok, second} = Vocabulary.add_word_to_deck(deck.id, word.id, user.id)

      assert first.id == second.id
    end

    test "add_word_to_deck/3 returns error when deck not found" do
      user = user_fixture()
      word = word_fixture()

      assert {:error, :deck_not_found} = Vocabulary.add_word_to_deck(999_999, word.id, user.id)
    end

    test "remove_word_from_deck/3 removes word from deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})
      word = word_fixture()

      {:ok, _} = Vocabulary.add_word_to_deck(deck.id, word.id, user.id)
      assert {:ok, _} = Vocabulary.remove_word_from_deck(deck.id, word.id, user.id)

      # Verify it's removed
      words = Vocabulary.list_words_in_deck(deck.id, user.id)
      refute Enum.any?(words, &(&1.id == word.id))
    end

    test "remove_word_from_deck/3 succeeds when word not in deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})
      word = word_fixture()

      assert {:ok, nil} = Vocabulary.remove_word_from_deck(deck.id, word.id, user.id)
    end

    test "remove_word_from_deck/3 returns error when deck not found" do
      user = user_fixture()
      word = word_fixture()

      assert {:error, :deck_not_found} =
               Vocabulary.remove_word_from_deck(999_999, word.id, user.id)
    end

    test "list_words_in_deck/2 returns all words in deck" do
      user = user_fixture()
      {:ok, deck} = Vocabulary.create_deck(user.id, %{name: "Test"})
      word1 = word_fixture()
      word2 = word_fixture()

      Vocabulary.add_word_to_deck(deck.id, word1.id, user.id)
      Vocabulary.add_word_to_deck(deck.id, word2.id, user.id)

      words = Vocabulary.list_words_in_deck(deck.id, user.id)

      assert length(words) == 2
      assert Enum.any?(words, &(&1.id == word1.id))
      assert Enum.any?(words, &(&1.id == word2.id))
    end

    test "list_words_in_deck/2 returns empty list when deck not found" do
      user = user_fixture()

      assert Vocabulary.list_words_in_deck(999_999, user.id) == []
    end
  end
end

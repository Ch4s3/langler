defmodule Langler.Vocabulary.DecksTest do
  use Langler.DataCase, async: true

  import Langler.{AccountsFixtures, VocabularyFixtures}

  alias Langler.Vocabulary.Decks

  describe "list_decks_with_words/1" do
    test "lists user decks with word counts" do
      user = user_fixture()
      deck1 = deck_fixture(%{user: user})
      deck2 = deck_fixture(%{user: user, name: "My Second Deck"})

      word1 = word_fixture()
      word2 = word_fixture(%{normalized_form: "otro"})

      Langler.Vocabulary.add_word_to_deck(deck1.id, word1.id, user.id)
      Langler.Vocabulary.add_word_to_deck(deck1.id, word2.id, user.id)
      Langler.Vocabulary.add_word_to_deck(deck2.id, word1.id, user.id)

      results = Decks.list_decks_with_words(user.id)

      assert length(results) >= 2
      deck1_result = Enum.find(results, &(&1.id == deck1.id))
      assert deck1_result.word_count == 2
    end
  end

  describe "follow_deck/2" do
    test "returns error when deck not found" do
      user = user_fixture()
      assert {:error, :deck_not_found} = Decks.follow_deck(-1, user.id)
    end

    test "allows following a public deck" do
      owner = user_fixture()
      follower = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "public"})

      assert {:ok, _follow} = Decks.follow_deck(deck.id, follower.id)
      assert Decks.following_deck?(deck.id, follower.id)
    end

    test "prevents following non-public decks" do
      owner = user_fixture()
      follower = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "private"})

      assert {:error, :deck_not_public} = Decks.follow_deck(deck.id, follower.id)
    end

    test "prevents following own deck" do
      user = user_fixture()
      deck = deck_fixture(%{user: user, visibility: "public"})

      assert {:error, :cannot_follow_own_deck} = Decks.follow_deck(deck.id, user.id)
    end
  end

  describe "unfollow_deck/2" do
    test "removes follow" do
      owner = user_fixture()
      follower = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "public"})

      {:ok, _} = Decks.follow_deck(deck.id, follower.id)
      assert {:ok, _} = Decks.unfollow_deck(deck.id, follower.id)
      refute Decks.following_deck?(deck.id, follower.id)
    end

    test "returns error when not following" do
      user = user_fixture()
      deck = deck_fixture(%{user: user_fixture(), visibility: "public"})

      assert {:error, :not_following} = Decks.unfollow_deck(deck.id, user.id)
    end
  end

  describe "copy_deck_to_user/2" do
    test "copies deck with words to new owner" do
      original_owner = user_fixture()
      new_owner = user_fixture()
      deck = deck_fixture(%{user: original_owner, name: "Original", visibility: "public"})

      word1 = word_fixture()
      word2 = word_fixture(%{normalized_form: "dos"})
      Langler.Vocabulary.add_word_to_deck(deck.id, word1.id, original_owner.id)
      Langler.Vocabulary.add_word_to_deck(deck.id, word2.id, original_owner.id)

      assert {:ok, copied_deck} = Decks.copy_deck_to_user(deck.id, new_owner.id)

      assert copied_deck.user_id == new_owner.id
      assert copied_deck.name == "Original (Copy)"
      assert copied_deck.visibility == "private"

      copied_words = Decks.list_deck_words(copied_deck.id, new_owner.id)
      assert length(copied_words) == 2
    end

    test "returns error when deck not found" do
      user = user_fixture()
      assert {:error, :deck_not_found} = Decks.copy_deck_to_user(-1, user.id)
    end
  end

  describe "freeze_followed_deck/2" do
    test "converts follow to owned copy" do
      owner = user_fixture()
      follower = user_fixture()
      deck = deck_fixture(%{user: owner, name: "Public Deck", visibility: "public"})

      word = word_fixture()
      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)

      {:ok, _} = Decks.follow_deck(deck.id, follower.id)
      assert Decks.following_deck?(deck.id, follower.id)

      assert {:ok, frozen_deck} = Decks.freeze_followed_deck(deck.id, follower.id)

      refute Decks.following_deck?(deck.id, follower.id)
      assert frozen_deck.user_id == follower.id
      assert frozen_deck.name == "Public Deck (Copy)"
    end
  end

  describe "share_deck/4" do
    test "shares deck with another user" do
      owner = user_fixture()
      recipient = user_fixture()
      deck = deck_fixture(%{user: owner})

      assert {:ok, share} = Decks.share_deck(deck.id, owner.id, recipient.id, "view")
      assert share.deck_id == deck.id
      assert share.shared_with_user_id == recipient.id
      assert share.permission == "view"
    end

    test "prevents sharing with self" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})

      assert {:error, :cannot_share_with_self} = Decks.share_deck(deck.id, user.id, user.id)
    end
  end

  describe "custom cards" do
    test "creates custom card" do
      user = user_fixture()
      _ = deck_fixture(%{user: user, is_default: true})

      attrs = %{
        front: "¿Qué hora es?",
        back: "What time is it?",
        language: "spanish"
      }

      assert {:ok, card} = Decks.create_custom_card(user.id, attrs)
      assert card.front == "¿Qué hora es?"
      assert card.back == "What time is it?"
      assert card.user_id == user.id
    end

    test "adds custom card to multiple decks" do
      user = user_fixture()
      _default_deck = deck_fixture(%{user: user, is_default: true})
      deck1 = deck_fixture(%{user: user})
      deck2 = deck_fixture(%{user: user, name: "Deck 2"})

      attrs = %{
        front: "Front",
        back: "Back",
        language: "spanish"
      }

      assert {:ok, _card} =
               Decks.add_new_custom_card_to_decks(user.id, attrs, [deck1.id, deck2.id])

      deck1_cards = Decks.list_deck_custom_cards(deck1.id, user.id)
      deck2_cards = Decks.list_deck_custom_cards(deck2.id, user.id)

      assert length(deck1_cards) >= 1
      assert length(deck2_cards) >= 1
    end

    test "updates custom card with ownership check" do
      user = user_fixture()
      other_user = user_fixture()

      {:ok, card} =
        Decks.create_custom_card(user.id, %{front: "Old", back: "Viejo", language: "spanish"})

      assert {:ok, updated} = Decks.update_custom_card(card.id, user.id, %{front: "New"})
      assert updated.front == "New"

      assert {:error, :not_found} =
               Decks.update_custom_card(card.id, other_user.id, %{front: "Hacked"})
    end

    test "deletes custom card with ownership check" do
      user = user_fixture()
      other_user = user_fixture()

      {:ok, card} =
        Decks.create_custom_card(user.id, %{front: "Front", back: "Back", language: "spanish"})

      assert {:error, :not_found} = Decks.delete_custom_card(card.id, other_user.id)
      assert {:ok, _} = Decks.delete_custom_card(card.id, user.id)
    end
  end

  describe "move_word_between_decks/4" do
    test "moves word from one deck to another" do
      user = user_fixture()
      deck1 = deck_fixture(%{user: user, name: "Deck 1"})
      deck2 = deck_fixture(%{user: user, name: "Deck 2"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck1.id, word.id, user.id)

      assert {:ok, _} = Decks.move_word_between_decks(word.id, deck1.id, deck2.id, user.id)

      deck1_words = Decks.list_deck_words(deck1.id, user.id)
      deck2_words = Decks.list_deck_words(deck2.id, user.id)

      refute Enum.any?(deck1_words, &(&1.id == word.id))
      assert Enum.any?(deck2_words, &(&1.id == word.id))
    end

    test "returns error when from_deck not found" do
      user = user_fixture()
      to_deck = deck_fixture(%{user: user})
      word = word_fixture()

      assert {:error, :from_deck_not_found} =
               Decks.move_word_between_decks(word.id, -1, to_deck.id, user.id)
    end

    test "returns error when to_deck not found" do
      user = user_fixture()
      from_deck = deck_fixture(%{user: user})
      word = word_fixture()
      Langler.Vocabulary.add_word_to_deck(from_deck.id, word.id, user.id)

      assert {:error, :to_deck_not_found} =
               Decks.move_word_between_decks(word.id, from_deck.id, -1, user.id)
    end
  end

  describe "bulk_add_words_to_deck/3" do
    test "adds multiple words to deck at once" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})

      word1 = word_fixture()
      word2 = word_fixture(%{normalized_form: "dos"})
      word3 = word_fixture(%{normalized_form: "tres"})

      assert {:ok, count} =
               Decks.bulk_add_words_to_deck(deck.id, [word1.id, word2.id, word3.id], user.id)

      assert count == 3

      words = Decks.list_deck_words(deck.id, user.id)
      assert length(words) == 3
    end

    test "returns error when deck not found" do
      user = user_fixture()
      word = word_fixture()

      assert {:error, :deck_not_found} =
               Decks.bulk_add_words_to_deck(-1, [word.id], user.id)
    end
  end

  describe "get_deck_with_contents/2" do
    test "returns deck with preloaded words and custom_cards for owner" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})
      word = word_fixture()
      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, user.id)

      result = Decks.get_deck_with_contents(deck.id, user.id)

      assert result.id == deck.id
      assert length(result.words) == 1
      assert hd(result.words).id == word.id
    end

    test "returns nil when viewer cannot access deck" do
      owner = user_fixture()
      other = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "private"})

      assert nil == Decks.get_deck_with_contents(deck.id, other.id)
    end
  end

  describe "list_public_decks/1" do
    test "returns public decks with optional search and language" do
      owner = user_fixture()

      deck =
        deck_fixture(%{user: owner, visibility: "public", name: "Spanish Verbs", language: "es"})

      results = Decks.list_public_decks(limit: 10)
      assert Enum.any?(results, &(&1.deck.id == deck.id))
      result = Enum.find(results, &(&1.deck.id == deck.id))
      assert result.follower_count >= 0

      search_results = Decks.list_public_decks(search: "Spanish", limit: 10)
      hit = Enum.find(search_results, &(&1.deck.id == deck.id))
      assert hit.deck.name == "Spanish Verbs"

      fr_results = Decks.list_public_decks(language: "fr", limit: 10)
      refute Enum.any?(fr_results, &(&1.deck.id == deck.id))
      es_results = Decks.list_public_decks(language: "es", limit: 10)
      hit_es = Enum.find(es_results, &(&1.deck.id == deck.id))
      assert hit_es.deck.language == "es"
    end
  end

  describe "list_followed_decks/1" do
    test "returns decks the user follows" do
      owner = user_fixture()
      follower = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "public"})

      {:ok, _} = Decks.follow_deck(deck.id, follower.id)

      [result] = Decks.list_followed_decks(follower.id)
      assert result.deck.id == deck.id
      assert result.owner.id == owner.id
    end
  end

  describe "list_shared_decks_for_user/1" do
    test "returns decks shared with the user" do
      owner = user_fixture()
      shared_user = user_fixture()
      deck = deck_fixture(%{user: owner})

      {:ok, _share} = Decks.share_deck(deck.id, owner.id, shared_user.id, "view")

      [result] = Decks.list_shared_decks_for_user(shared_user.id)
      assert result.deck.id == deck.id
      assert result.permission == "view"
    end
  end

  describe "unshare_deck/2" do
    test "removes share and returns ok" do
      owner = user_fixture()
      shared_user = user_fixture()
      deck = deck_fixture(%{user: owner})
      {:ok, _} = Decks.share_deck(deck.id, owner.id, shared_user.id, "view")

      assert {:ok, _} = Decks.unshare_deck(deck.id, shared_user.id)
      assert [] == Decks.list_shared_decks_for_user(shared_user.id)
    end

    test "returns error when share not found" do
      owner = user_fixture()
      other = user_fixture()
      deck = deck_fixture(%{user: owner})

      assert {:error, :share_not_found} = Decks.unshare_deck(deck.id, other.id)
    end
  end

  describe "update_share_permission/3" do
    test "updates permission" do
      owner = user_fixture()
      shared_user = user_fixture()
      deck = deck_fixture(%{user: owner})
      {:ok, _} = Decks.share_deck(deck.id, owner.id, shared_user.id, "view")

      assert {:ok, updated} = Decks.update_share_permission(deck.id, shared_user.id, "edit")
      assert updated.permission == "edit"
    end

    test "returns error when share not found" do
      assert {:error, :share_not_found} =
               Decks.update_share_permission(-1, -1, "edit")
    end
  end

  describe "add_custom_card_to_deck/3" do
    test "adds card to deck" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})
      {:ok, card} = Decks.create_custom_card(user.id, %{front: "F", back: "B", language: "es"})

      assert {:ok, _} = Decks.add_custom_card_to_deck(deck.id, card.id, user.id)
      cards = Decks.list_deck_custom_cards(deck.id, user.id)
      assert Enum.any?(cards, &(&1.id == card.id))
    end

    test "returns error when deck not found" do
      user = user_fixture()
      {:ok, card} = Decks.create_custom_card(user.id, %{front: "F", back: "B", language: "es"})
      assert {:error, :deck_not_found} = Decks.add_custom_card_to_deck(-1, card.id, user.id)
    end

    test "returns error when custom card not found" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})

      assert {:error, :custom_card_not_found} =
               Decks.add_custom_card_to_deck(deck.id, -1, user.id)
    end

    test "returns error when card belongs to another user" do
      owner = user_fixture()
      other = user_fixture()
      deck = deck_fixture(%{user: other})
      {:ok, card} = Decks.create_custom_card(owner.id, %{front: "F", back: "B", language: "es"})

      assert {:error, :not_card_owner} =
               Decks.add_custom_card_to_deck(deck.id, card.id, other.id)
    end
  end

  describe "remove_custom_card_from_deck/3" do
    test "removes card from deck" do
      user = user_fixture()
      _default = deck_fixture(%{user: user, is_default: true})
      deck = deck_fixture(%{user: user})

      {:ok, card} =
        Decks.add_new_custom_card_to_decks(user.id, %{front: "F", back: "B", language: "es"}, [
          deck.id
        ])

      assert {:ok, :removed} = Decks.remove_custom_card_from_deck(deck.id, card.id, user.id)
      assert [] == Decks.list_deck_custom_cards(deck.id, user.id)
    end

    test "returns error when deck not found" do
      user = user_fixture()
      {:ok, card} = Decks.create_custom_card(user.id, %{front: "F", back: "B", language: "es"})
      assert {:error, :deck_not_found} = Decks.remove_custom_card_from_deck(-1, card.id, user.id)
    end

    test "returns error when card not in deck" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})
      {:ok, card} = Decks.create_custom_card(user.id, %{front: "F", back: "B", language: "es"})

      assert {:error, :not_in_deck} =
               Decks.remove_custom_card_from_deck(deck.id, card.id, user.id)
    end
  end

  describe "list_study_cards_for_user/1" do
    test "returns words and custom cards from owned decks" do
      user = user_fixture()
      deck = deck_fixture(%{user: user})
      word = word_fixture()
      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, user.id)
      {:ok, card} = Decks.create_custom_card(user.id, %{front: "Q", back: "A", language: "es"})
      Decks.add_custom_card_to_deck(deck.id, card.id, user.id)

      cards = Decks.list_study_cards_for_user(user.id)
      word_entries = Enum.filter(cards, &(&1.type == "word"))
      custom_entries = Enum.filter(cards, &(&1.type == "custom_card"))
      assert Enum.any?(word_entries, &(&1.content.id == word.id))
      assert Enum.any?(custom_entries, &(&1.content.id == card.id))
    end
  end

  describe "create_deck_with_words/3" do
    test "creates deck and adds words in one transaction" do
      user = user_fixture()
      word1 = word_fixture()
      word2 = word_fixture(%{normalized_form: "dos"})

      assert {:ok, deck} =
               Decks.create_deck_with_words(
                 user.id,
                 %{name: "New Deck", language: "es", visibility: "private"},
                 [word1.id, word2.id]
               )

      assert deck.name == "New Deck"
      words = Decks.list_deck_words(deck.id, user.id)
      assert length(words) == 2
    end
  end
end

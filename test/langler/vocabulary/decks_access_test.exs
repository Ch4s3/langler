defmodule Langler.Vocabulary.DecksAccessTest do
  use Langler.DataCase, async: true

  import Langler.{AccountsFixtures, VocabularyFixtures}

  alias Langler.Vocabulary.Decks

  describe "deck access control" do
    test "owner can view their private deck" do
      owner = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "private"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)

      words = Decks.list_deck_words(deck.id, owner.id)
      assert length(words) == 1
    end

    test "non-owner cannot view private deck" do
      owner = user_fixture()
      other_user = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "private"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)

      words = Decks.list_deck_words(deck.id, other_user.id)
      assert words == []
    end

    test "anyone can view public deck" do
      owner = user_fixture()
      viewer = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "public"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)

      words = Decks.list_deck_words(deck.id, viewer.id)
      assert length(words) == 1
    end

    test "shared user can view shared deck" do
      owner = user_fixture()
      shared_user = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "shared"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)
      {:ok, _share} = Decks.share_deck(deck.id, owner.id, shared_user.id, "view")

      words = Decks.list_deck_words(deck.id, shared_user.id)
      assert length(words) == 1
    end

    test "non-shared user cannot view shared deck" do
      owner = user_fixture()
      shared_user = user_fixture()
      other_user = user_fixture()
      deck = deck_fixture(%{user: owner, visibility: "shared"})
      word = word_fixture()

      Langler.Vocabulary.add_word_to_deck(deck.id, word.id, owner.id)
      {:ok, _share} = Decks.share_deck(deck.id, owner.id, shared_user.id, "view")

      words = Decks.list_deck_words(deck.id, other_user.id)
      assert words == []
    end
  end

  describe "custom card access" do
    test "custom cards follow same access rules as decks" do
      owner = user_fixture()
      viewer = user_fixture()
      _default_deck = deck_fixture(%{user: owner, is_default: true})
      public_deck = deck_fixture(%{user: owner, visibility: "public"})

      {:ok, card} =
        Decks.add_new_custom_card_to_decks(
          owner.id,
          %{front: "Test", back: "Prueba", language: "spanish"},
          [public_deck.id]
        )

      # Viewer can see custom card in public deck
      cards = Decks.list_deck_custom_cards(public_deck.id, viewer.id)
      assert Enum.any?(cards, &(&1.id == card.id))
    end

    test "private deck custom cards not visible to others" do
      owner = user_fixture()
      viewer = user_fixture()
      _default_deck = deck_fixture(%{user: owner, is_default: true})
      private_deck = deck_fixture(%{user: owner, visibility: "private"})

      {:ok, _card} =
        Decks.add_new_custom_card_to_decks(
          owner.id,
          %{front: "Secret", back: "Secreto", language: "spanish"},
          [private_deck.id]
        )

      # Viewer cannot see custom cards in private deck
      cards = Decks.list_deck_custom_cards(private_deck.id, viewer.id)
      assert cards == []
    end
  end
end

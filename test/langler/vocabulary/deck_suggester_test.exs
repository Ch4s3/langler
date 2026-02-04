defmodule Langler.Vocabulary.DeckSuggesterTest do
  use Langler.DataCase, async: true

  import Langler.{AccountsFixtures, VocabularyFixtures}

  alias Langler.Vocabulary
  alias Langler.Vocabulary.DeckSuggester

  describe "suggest_groupings/2" do
    test "returns error when user has no ungrouped words" do
      user = user_fixture()
      _ = Vocabulary.get_or_create_default_deck(user.id)
      # No words in default deck

      assert {:error, :no_ungrouped_words} = DeckSuggester.suggest_groupings(user.id)
    end

    test "returns error when too few ungrouped words (under 10)" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      words =
        for _ <- 1..5 do
          w = word_fixture()
          Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
          w
        end

      assert length(words) == 5
      assert {:error, {:too_few_words, 5}} = DeckSuggester.suggest_groupings(user.id)
    end

    test "returns error when user has no LLM config" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      for _ <- 1..12 do
        w = word_fixture()
        Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
      end

      assert {:error, :no_llm_config} = DeckSuggester.suggest_groupings(user.id)
    end

    test "parses valid JSON with inject_response and returns suggestions" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      words =
        for i <- 1..12 do
          w = word_fixture(%{normalized_form: "word#{i}"})
          Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
          w
        end

      word_forms = Enum.map(words, & &1.normalized_form)
      [w1, w2, w3 | _] = word_forms

      json = """
      {
        "suggestions": [
          {
            "name": "Test Deck",
            "description": "Test grouping",
            "category": "thematic",
            "words": ["#{w1}", "#{w2}", "#{w3}"],
            "confidence": 0.9
          }
        ]
      }
      """

      assert {:ok, suggestions} =
               DeckSuggester.suggest_groupings(user.id, inject_response: json)

      assert length(suggestions) == 1
      [s] = suggestions
      assert s.name == "Test Deck"
      assert s.description == "Test grouping"
      assert s.category == "thematic"
      assert s.words == [w1, w2, w3]
      assert length(s.word_ids) == 3
      assert s.confidence == 0.9
    end

    test "strips markdown code blocks from inject_response before parsing" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      for i <- 1..12 do
        w = word_fixture(%{normalized_form: "term#{i}"})
        Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
      end

      json_with_fence = """
      ```json
      {"suggestions": [{"name": "A", "description": "B", "category": "thematic", "words": ["term1", "term2", "term3"], "confidence": 0.8}]}
      ```
      """

      assert {:ok, [s]} = DeckSuggester.suggest_groupings(user.id, inject_response: json_with_fence)
      assert s.name == "A"
    end

    test "returns error for invalid JSON with inject_response" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      for _ <- 1..12 do
        w = word_fixture()
        Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
      end

      assert {:error, :invalid_json} =
               DeckSuggester.suggest_groupings(user.id, inject_response: "not valid json {")
    end

    test "returns error when JSON missing suggestions key with inject_response" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      for _ <- 1..12 do
        w = word_fixture()
        Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
      end

      assert {:error, :invalid_format} =
               DeckSuggester.suggest_groupings(user.id, inject_response: "{\"other\": []}")
    end

    test "filters out suggestions with fewer than 3 words" do
      user = user_fixture()
      {:ok, default_deck} = Vocabulary.get_or_create_default_deck(user.id)

      words =
        for i <- 1..12 do
          w = word_fixture(%{normalized_form: "x#{i}"})
          Vocabulary.add_word_to_deck(default_deck.id, w.id, user.id)
          w
        end

      [a, b | _] = Enum.map(words, & &1.normalized_form)

      json = """
      {
        "suggestions": [
          {"name": "Too small", "description": "D", "category": "thematic", "words": ["#{a}", "#{b}"], "confidence": 0.5}
        ]
      }
      """

      assert {:ok, []} = DeckSuggester.suggest_groupings(user.id, inject_response: json)
    end
  end
end

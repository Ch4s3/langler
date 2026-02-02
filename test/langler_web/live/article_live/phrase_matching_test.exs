defmodule LanglerWeb.ArticleLive.PhraseMatchingTest do
  use Langler.DataCase, async: true

  alias LanglerWeb.ArticleLive.Show

  describe "find_all_phrase_occurrences/3" do
    @tag :phrase_matching
    test "matches a two-word phrase" do
      lexical_tokens = [{0, "hola"}, {2, "mundo"}, {4, "amigo"}]
      phrase_parts = ["hola", "mundo"]
      used = MapSet.new()

      matches = Show.find_all_phrase_occurrences(lexical_tokens, phrase_parts, used)

      assert matches == [[0, 2]]
    end

    @tag :phrase_matching
    test "finds multiple non-overlapping occurrences" do
      lexical_tokens = [
        {0, "hola"},
        {2, "mundo"},
        {4, "hola"},
        {6, "mundo"}
      ]

      phrase_parts = ["hola", "mundo"]
      used = MapSet.new()

      matches = Show.find_all_phrase_occurrences(lexical_tokens, phrase_parts, used)

      assert length(matches) == 2
      assert [0, 2] in matches
      assert [4, 6] in matches
    end

    @tag :phrase_matching
    test "respects used tokens" do
      lexical_tokens = [{0, "hola"}, {2, "mundo"}, {4, "amigo"}]
      phrase_parts = ["hola", "mundo"]
      used = MapSet.new([0])

      matches = Show.find_all_phrase_occurrences(lexical_tokens, phrase_parts, used)

      assert matches == []
    end

    @tag :phrase_matching
    test "does not match partial phrases" do
      lexical_tokens = [{0, "hola"}, {2, "amigo"}]
      phrase_parts = ["hola", "mundo"]
      used = MapSet.new()

      matches = Show.find_all_phrase_occurrences(lexical_tokens, phrase_parts, used)

      assert matches == []
    end
  end

  describe "find_phrase_matches/2" do
    @tag :phrase_matching
    test "matches simple phrase" do
      lexical_tokens = [{0, "buenos"}, {2, "dias"}]

      phrases = [
        %{
          word_id: 1,
          normalized_parts: ["buenos", "dias"],
          original_form: "buenos dias"
        }
      ]

      matches = Show.find_phrase_matches(lexical_tokens, phrases)

      assert Map.keys(matches) |> Enum.sort() == [0, 2]
      assert matches[0].word_id == 1
      assert matches[2].word_id == 1
    end

    @tag :phrase_matching
    test "longer phrases take precedence" do
      lexical_tokens = [{0, "buenos"}, {2, "dias"}, {4, "amigo"}]

      phrases = [
        %{
          word_id: 2,
          normalized_parts: ["buenos", "dias"],
          original_form: "buenos dias"
        },
        %{word_id: 1, normalized_parts: ["buenos"], original_form: "buenos"}
      ]

      matches = Show.find_phrase_matches(lexical_tokens, phrases)

      # Should match the longer phrase, not the single word
      assert matches[0].word_id == 2
      assert matches[2].word_id == 2
      refute Map.has_key?(matches, 4)
    end

    @tag :phrase_matching
    test "non-overlapping matches work" do
      lexical_tokens = [{0, "uno"}, {2, "dos"}, {4, "tres"}, {6, "cuatro"}]

      phrases = [
        %{word_id: 1, normalized_parts: ["uno", "dos"], original_form: "uno dos"},
        %{word_id: 2, normalized_parts: ["tres", "cuatro"], original_form: "tres cuatro"}
      ]

      matches = Show.find_phrase_matches(lexical_tokens, phrases)

      assert length(Map.keys(matches)) == 4
      assert matches[0].word_id == 1
      assert matches[2].word_id == 1
      assert matches[4].word_id == 2
      assert matches[6].word_id == 2
    end

    @tag :phrase_matching
    test "empty phrase list returns empty map" do
      lexical_tokens = [{0, "hola"}, {2, "mundo"}]
      phrases = []

      matches = Show.find_phrase_matches(lexical_tokens, phrases)

      assert matches == %{}
    end
  end
end

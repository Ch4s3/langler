defmodule Langler.Content.IdiomSpanMatcherTest do
  use ExUnit.Case, async: true

  alias Langler.Content.IdiomSpanMatcher

  describe "find_spans/2" do
    test "finds phrase at start of sentence" do
      # Use tokenizer to get exact token list for "dar en el clavo ."
      content = "dar en el clavo."
      phrases = ["dar en el clavo"]
      spans = IdiomSpanMatcher.find_spans(content, phrases)
      assert length(spans) == 1
      assert hd(spans).phrase == "dar en el clavo"
      assert hd(spans).start_position == 0
      # "dar" " " "en" " " "el" " " "clavo" "." -> end is index 6 (clavo)
      assert hd(spans).end_position == 6
    end

    test "returns empty when phrase not in sentence" do
      content = "Hola mundo."
      spans = IdiomSpanMatcher.find_spans(content, ["dar en el clavo"])
      assert spans == []
    end

    test "returns empty when phrases list is empty" do
      content = "Hola mundo."
      assert IdiomSpanMatcher.find_spans(content, []) == []
    end

    test "handles multiple phrases" do
      content = "dar en el clavo y estar en las nubes."
      phrases = ["dar en el clavo", "estar en las nubes"]
      spans = IdiomSpanMatcher.find_spans(content, phrases)
      assert length(spans) == 2
      phrases_found = Enum.map(spans, & &1.phrase) |> Enum.sort()
      assert "dar en el clavo" in phrases_found
      assert "estar en las nubes" in phrases_found
    end
  end
end

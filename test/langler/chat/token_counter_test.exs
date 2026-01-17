defmodule Langler.Chat.TokenCounterTest do
  use ExUnit.Case, async: true

  alias Langler.Chat.TokenCounter

  describe "count_tokens/1" do
    test "counts approximate tokens with a minimum of one" do
      assert TokenCounter.count_tokens("12345678") == 2
      assert TokenCounter.count_tokens("") == 1
    end

    test "returns zero for non-binary input" do
      assert TokenCounter.count_tokens(nil) == 0
      assert TokenCounter.count_tokens(123) == 0
    end
  end

  describe "count_message_tokens/1" do
    test "sums token counts across message maps" do
      messages = [
        %{content: "1234"},
        %{content: "12345678"},
        %{content: nil},
        %{role: "user"}
      ]

      assert TokenCounter.count_message_tokens(messages) == 3
    end

    test "returns zero for non-list input" do
      assert TokenCounter.count_message_tokens(nil) == 0
    end
  end

  describe "format_count/1" do
    test "formats large counts with a k suffix" do
      assert TokenCounter.format_count(1_234) == "~1.2k tokens"
      assert TokenCounter.format_count(12_000) == "~12.0k tokens"
    end

    test "formats small counts without a suffix" do
      assert TokenCounter.format_count(567) == "~567 tokens"
      assert TokenCounter.format_count(0) == "~0 tokens"
      assert TokenCounter.format_count("nope") == "~0 tokens"
    end
  end
end

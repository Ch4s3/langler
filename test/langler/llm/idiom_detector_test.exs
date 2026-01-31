defmodule Langler.LLM.IdiomDetectorTest do
  use ExUnit.Case, async: true

  alias Langler.LLM.IdiomDetector

  describe "parse_response/2" do
    test "parses valid JSON with multiple idiom results" do
      content = """
      [
        {"sentence_index": 0, "idioms": ["dar en el clavo", "estar en las nubes"]},
        {"sentence_index": 1, "idioms": []}
      ]
      """

      assert {:ok, results} = IdiomDetector.parse_response(content, 2)
      assert length(results) == 2
      assert Enum.at(results, 0).sentence_index == 0
      assert Enum.at(results, 0).phrases == ["dar en el clavo", "estar en las nubes"]
      assert Enum.at(results, 1).sentence_index == 1
      assert Enum.at(results, 1).phrases == []
    end

    test "handles empty idiom list" do
      content = "[]"
      assert {:ok, []} = IdiomDetector.parse_response(content, 10)
    end

    test "strips markdown code block" do
      content = """
      ```json
      [{"sentence_index": 0, "idioms": ["phrase one"]}]
      ```
      """

      assert {:ok, [%{phrases: ["phrase one"]}]} = IdiomDetector.parse_response(content, 1)
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = IdiomDetector.parse_response("{ invalid }", 1)
    end

    test "returns error for non-array decoded content" do
      assert {:error, :invalid_structure} = IdiomDetector.parse_response("{}", 1)
    end

    test "returns error when sentence_index out of range" do
      content = ~s([{"sentence_index": 5, "idioms": ["x"]}])
      assert {:error, :invalid_sentence_index} = IdiomDetector.parse_response(content, 3)
    end

    test "filters out rows with missing or invalid fields" do
      content = """
      [
        {"sentence_index": 0, "idioms": ["ok"]},
        {"sentence_index": 1},
        {"wrong": "shape"}
      ]
      """

      assert {:ok, results} = IdiomDetector.parse_response(content, 2)
      assert length(results) == 1
      assert hd(results).phrases == ["ok"]
    end
  end
end

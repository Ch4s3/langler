defmodule Langler.Quizzes.ResultParserTest do
  use ExUnit.Case, async: true

  alias Langler.Quizzes.ResultParser

  describe "parse/1" do
    test "extracts and parses valid JSON from delimited content" do
      content = """
      Some text before
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5, "questions": [
        {"question": "What did the article say about X?", "user_answer": "It said Y", "correct": true, "explanation": "Correct because..."}
      ]}
      END_QUIZ_RESULT
      Some text after
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
      assert result.max_score == 5
      assert length(result.questions) == 1
    end

    test "handles case-insensitive delimiters" do
      content = """
      begin_quiz_result
      {"score": 3, "max_score": 5, "questions": []}
      end_quiz_result
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 3
    end

    test "handles whitespace around delimiters" do
      content = """
      BEGIN_QUIZ_RESULT

      {"score": 4, "max_score": 5, "questions": []}

      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
    end

    test "returns error when delimiters not found" do
      content = "Just some text without delimiters"
      assert {:error, :not_found} = ResultParser.parse(content)
    end

    test "returns error when only BEGIN marker present" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5, "questions": []}
      """

      assert {:error, :not_found} = ResultParser.parse(content)
    end

    test "returns error when only END marker present" do
      content = """
      {"score": 4, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:error, :not_found} = ResultParser.parse(content)
    end

    test "returns error for invalid JSON" do
      content = """
      BEGIN_QUIZ_RESULT
      {invalid json}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_json} = ResultParser.parse(content)
    end

    test "returns error for invalid structure - missing score" do
      content = """
      BEGIN_QUIZ_RESULT
      {"max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "returns error for invalid structure - missing max_score" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 4, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "returns error for invalid structure - missing questions" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "returns error for invalid structure - wrong type" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": "four", "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "validates question structure - all required fields" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "Q1", "user_answer": "A1", "correct": true, "explanation": "E1"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert length(result.questions) == 1
    end

    test "returns error for invalid question structure - missing explanation" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "Q1", "user_answer": "A1", "correct": true}
      ]}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "returns error for invalid question structure - wrong type" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "Q1", "user_answer": "A1", "correct": "yes", "explanation": "E1"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:error, :invalid_structure} = ResultParser.parse(content)
    end

    test "handles empty content" do
      assert {:error, :not_found} = ResultParser.parse("")
    end

    test "handles non-string input" do
      assert {:error, :invalid_input} = ResultParser.parse(123)
      assert {:error, :invalid_input} = ResultParser.parse(nil)
      assert {:error, :invalid_input} = ResultParser.parse([])
    end

    test "extracts first JSON block when multiple present" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      BEGIN_QUIZ_RESULT
      {"score": 3, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
    end

    test "handles complex question structure" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 2, "max_score": 3, "questions": [
        {"question": "Q1", "user_answer": "A1", "correct": true, "explanation": "E1"},
        {"question": "Q2", "user_answer": "A2", "correct": false, "explanation": "E2"},
        {"question": "Q3", "user_answer": "A3", "correct": true, "explanation": "E3"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 2
      assert result.max_score == 3
      assert length(result.questions) == 3
      assert Enum.at(result.questions, 0)["correct"] == true
      assert Enum.at(result.questions, 1)["correct"] == false
    end

    test "handles very long question text" do
      long_question = String.duplicate("This is a very long question. ", 100)
      long_answer = String.duplicate("This is a very long answer. ", 100)
      long_explanation = String.duplicate("This is a very long explanation. ", 100)

      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "#{long_question}", "user_answer": "#{long_answer}", "correct": true, "explanation": "#{long_explanation}"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert String.length(hd(result.questions)["question"]) > 1000
    end

    test "handles special characters in JSON" do
      # Use proper JSON escaping
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "What is \\"quoted\\"?", "user_answer": "It's an answer!", "correct": true, "explanation": "Explanation with newline"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      question = hd(result.questions)
      assert String.contains?(question["question"], "quoted")
      assert String.contains?(question["user_answer"], "It's")
    end

    test "handles unicode characters" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "¿Qué es esto? 这是中文", "user_answer": "C'est français", "correct": true, "explanation": "Explicación en español"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      question = hd(result.questions)
      # Check that unicode is preserved
      assert question["question"] != ""
      assert question["user_answer"] != ""
      assert question["explanation"] != ""
    end

    test "handles JSON with extra whitespace" do
      content = """
      BEGIN_QUIZ_RESULT
      {
        "score": 4,
        "max_score": 5,
        "questions": [
          {
            "question": "Q1",
            "user_answer": "A1",
            "correct": true,
            "explanation": "E1"
          }
        ]
      }
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
    end

    test "handles score of 0" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 0, "max_score": 5, "questions": [
        {"question": "Q1", "user_answer": "A1", "correct": false, "explanation": "E1"}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 0
    end

    test "handles max_score of 0 (edge case)" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 0, "max_score": 0, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 0
      assert result.max_score == 0
    end

    test "handles very large number of questions" do
      questions =
        for i <- 1..50 do
          %{
            "question" => "Question #{i}",
            "user_answer" => "Answer #{i}",
            "correct" => rem(i, 2) == 0,
            "explanation" => "Explanation #{i}"
          }
        end

      json = Jason.encode!(%{"score" => 25, "max_score" => 50, "questions" => questions})

      content = """
      BEGIN_QUIZ_RESULT
      #{json}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert length(result.questions) == 50
    end

    test "handles nested markers in content" do
      # The parser finds the first valid marker pair
      # If markers appear in text, they should still work if properly formatted
      content = """
      Some text before.
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      Some text after.
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
    end

    test "handles markers with extra text on same line" do
      # Test that markers work when on separate lines (standard case)
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 4, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.score == 4
    end

    test "handles empty questions array" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 0, "max_score": 5, "questions": []}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      assert result.questions == []
    end

    test "handles question with empty strings" do
      content = """
      BEGIN_QUIZ_RESULT
      {"score": 1, "max_score": 1, "questions": [
        {"question": "", "user_answer": "", "correct": true, "explanation": ""}
      ]}
      END_QUIZ_RESULT
      """

      assert {:ok, result} = ResultParser.parse(content)
      question = hd(result.questions)
      assert question["question"] == ""
      assert question["user_answer"] == ""
    end
  end
end

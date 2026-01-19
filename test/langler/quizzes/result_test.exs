defmodule Langler.Quizzes.ResultTest do
  use ExUnit.Case, async: true

  alias Langler.Quizzes.Result

  describe "from_map/1" do
    test "builds a Result struct when the structure is valid" do
      payload = %{
        "score" => 2,
        "max_score" => 4,
        "questions" => [
          %{
            "question" => "Sample?",
            "user_answer" => "Answer",
            "correct" => true,
            "explanation" => "Because"
          }
        ]
      }

      assert {:ok, %Result{score: 2, max_score: 4, questions: questions}} =
               Result.from_map(payload)

      assert length(questions) == 1
    end

    test "returns error when required top-level keys are missing" do
      assert {:error, :invalid_structure} = Result.from_map(%{})
    end

    test "returns error when a question is missing keys" do
      payload = %{
        "score" => 1,
        "max_score" => 1,
        "questions" => [
          %{
            "question" => "Q1",
            "user_answer" => "A1",
            "correct" => true
          }
        ]
      }

      assert {:error, :invalid_question_structure} = Result.from_map(payload)
    end
  end

  describe "percentage/1" do
    test "computes the percentage when max_score is positive" do
      result = %Result{score: 3, max_score: 5}

      assert Result.percentage(result) == 60.0
    end

    test "returns 0.0 when max_score is not positive" do
      result = %Result{score: 2, max_score: 0}

      assert Result.percentage(result) == 0.0
    end
  end

  describe "badge_class/1" do
    test "returns success when percentage is >= 80" do
      result = %Result{score: 8, max_score: 10}

      assert Result.badge_class(result) == "badge-success"
    end

    test "returns warning when percentage is between 60 and 79" do
      result = %Result{score: 6, max_score: 10}

      assert Result.badge_class(result) == "badge-warning"
    end

    test "returns error for percentages below 60" do
      result = %Result{score: 1, max_score: 5}

      assert Result.badge_class(result) == "badge-error"
    end
  end

  describe "to_map/1" do
    test "serializes the struct back to a map" do
      result = %Result{score: 4, max_score: 5, questions: []}

      assert Result.to_map(result) == %{
               "score" => 4,
               "max_score" => 5,
               "questions" => []
             }
    end
  end
end

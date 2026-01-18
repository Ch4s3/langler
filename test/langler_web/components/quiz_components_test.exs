defmodule LanglerWeb.QuizComponentsTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Langler.Quizzes.Result
  alias LanglerWeb.QuizComponents

  describe "quiz components" do
    setup do
      result = %Result{
        score: 8,
        max_score: 10,
        questions: [
          %{
            "question" => "Question 1",
            "user_answer" => "Answer 1",
            "correct" => true,
            "explanation" => "Explanation"
          }
        ]
      }

      %{result: result}
    end

    test "quiz_score_badge renders score and classes", %{result: result} do
      html = render_component(&QuizComponents.quiz_score_badge/1, result: result, class: "custom")

      assert html =~ "8/10"
      assert html =~ Result.badge_class(result)
      assert html =~ "custom"
    end

    test "quiz_percentage renders percentage", %{result: result} do
      html =
        render_component(&QuizComponents.quiz_percentage/1,
          result: result,
          class: "custom-percent"
        )

      assert html =~ "80.0%"
      assert html =~ "custom-percent"
    end

    test "quiz_question_card highlights answer correctness", %{result: result} do
      question = List.first(result.questions)
      html = render_component(&QuizComponents.quiz_question_card/1, question: question, index: 0)

      assert html =~ "Question 1"
      assert html =~ "Answer 1"
      assert html =~ "Explanation"
      assert html =~ "Correct"
    end
  end
end

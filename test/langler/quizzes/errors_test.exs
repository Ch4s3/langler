defmodule Langler.Quizzes.ErrorsTest do
  use ExUnit.Case, async: true

  alias Langler.Quizzes.Errors

  describe "error helpers" do
    test "invalid_session returns exception with metadata" do
      error = Errors.invalid_session()

      assert %Errors{type: :invalid_session, message: "Invalid quiz session"} = error
    end

    test "missing_article_id returns descriptive message" do
      error = Errors.missing_article_id()

      assert %Errors{
               type: :missing_article_id,
               message: "Article ID is required for quiz operations"
             } = error
    end

    test "invalid_result_format returns mesage about format" do
      error = Errors.invalid_result_format()

      assert %Errors{
               type: :invalid_result_format,
               message: "Quiz result format is invalid"
             } = error
    end
  end
end

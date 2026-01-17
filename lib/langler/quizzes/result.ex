defmodule Langler.Quizzes.Result do
  @moduledoc """
  Struct for representing quiz results with type safety.

  Provides a structured way to work with quiz results instead of raw maps.
  """

  @type question :: %{
          question: String.t(),
          user_answer: String.t(),
          correct: boolean(),
          explanation: String.t()
        }

  @type t :: %__MODULE__{
          score: integer(),
          max_score: integer(),
          questions: [question()]
        }

  defstruct [:score, :max_score, questions: []]

  @doc """
  Creates a Result struct from a map (typically from JSON parsing).

  Validates the structure and returns `{:ok, result}` or `{:error, reason}`.
  """
  def from_map(%{"score" => score, "max_score" => max_score, "questions" => questions})
      when is_integer(score) and is_integer(max_score) and is_list(questions) do
    if Enum.all?(questions, &valid_question?/1) do
      {:ok,
       %__MODULE__{
         score: score,
         max_score: max_score,
         questions: questions
       }}
    else
      {:error, :invalid_question_structure}
    end
  end

  def from_map(_), do: {:error, :invalid_structure}

  @doc """
  Converts a Result struct back to a map (for JSON serialization).
  """
  def to_map(%__MODULE__{} = result) do
    %{
      "score" => result.score,
      "max_score" => result.max_score,
      "questions" => result.questions
    }
  end

  @doc """
  Calculates the percentage score.
  """
  def percentage(%__MODULE__{score: score, max_score: max_score}) when max_score > 0 do
    Float.round(score / max_score * 100, 1)
  end

  def percentage(_), do: 0.0

  @doc """
  Gets the score badge class based on percentage.
  """
  def badge_class(%__MODULE__{} = result) do
    percentage = percentage(result)

    cond do
      percentage >= 80 -> "badge-success"
      percentage >= 60 -> "badge-warning"
      true -> "badge-error"
    end
  end

  defp valid_question?(%{
         "question" => q,
         "user_answer" => a,
         "correct" => c,
         "explanation" => e
       })
       when is_binary(q) and is_binary(a) and is_boolean(c) and is_binary(e) do
    true
  end

  defp valid_question?(_), do: false
end

defmodule Langler.Quizzes.ArticleQuizAttempt do
  @moduledoc """
  Ecto schema for article quiz attempts.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "article_quiz_attempts" do
    belongs_to :user, Langler.Accounts.User
    belongs_to :article, Langler.Content.Article
    belongs_to :chat_session, Langler.Chat.ChatSession
    field :attempt_number, :integer
    field :score, :integer
    field :max_score, :integer
    field :result_json, :map
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :user_id,
      :article_id,
      :chat_session_id,
      :attempt_number,
      :score,
      :max_score,
      :result_json,
      :started_at,
      :completed_at
    ])
    |> validate_required([:user_id, :article_id, :attempt_number])
    |> validate_number(:attempt_number, greater_than: 0)
    |> validate_number(:score, greater_than_or_equal_to: 0)
    |> validate_number(:max_score, greater_than: 0)
    |> validate_result_json()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:article_id)
    |> foreign_key_constraint(:chat_session_id)
  end

  defp validate_result_json(changeset) do
    case get_change(changeset, :result_json) do
      nil ->
        changeset

      result_json when is_map(result_json) ->
        changeset
        |> validate_result_structure(result_json)
        |> validate_score_consistency(result_json)

      _ ->
        add_error(changeset, :result_json, "must be a map")
    end
  end

  defp validate_result_structure(changeset, result_json) do
    required_fields = ["score", "max_score", "questions"]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(result_json, &1))
      |> Enum.map(&"missing #{&1}")

    if Enum.empty?(missing_fields) do
      # Validate questions array structure
      questions = Map.get(result_json, "questions", [])

      if is_list(questions) do
        validate_questions_structure(changeset, questions)
      else
        add_error(changeset, :result_json, "questions must be a list")
      end
    else
      add_error(changeset, :result_json, Enum.join(missing_fields, ", "))
    end
  end

  defp validate_questions_structure(changeset, questions) do
    invalid_questions =
      questions
      |> Enum.with_index()
      |> Enum.filter(fn {question, _idx} ->
        not is_map(question) or
          not Map.has_key?(question, "question") or
          not Map.has_key?(question, "user_answer") or
          not Map.has_key?(question, "correct") or
          not Map.has_key?(question, "explanation")
      end)

    if Enum.empty?(invalid_questions) do
      changeset
    else
      add_error(
        changeset,
        :result_json,
        "questions must have question, user_answer, correct, and explanation fields"
      )
    end
  end

  defp validate_score_consistency(changeset, result_json) do
    score = get_change(changeset, :score)
    max_score = get_change(changeset, :max_score)
    result_score = Map.get(result_json, "score")
    result_max_score = Map.get(result_json, "max_score")

    # Use changeset values if available, otherwise use result_json values
    final_score = score || result_score
    final_max_score = max_score || result_max_score

    if final_score && final_max_score && final_score > final_max_score do
      add_error(changeset, :score, "cannot be greater than max_score")
    else
      changeset
    end
  end
end

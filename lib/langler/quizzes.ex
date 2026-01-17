defmodule Langler.Quizzes do
  @moduledoc """
  Context module for managing article quiz attempts.

  Provides functions for creating, querying, and managing quiz attempts
  including scoring, retakes, and best score lookups.
  """

  import Ecto.Query, warn: false

  alias Langler.Quizzes.ArticleQuizAttempt
  alias Langler.Repo

  # Quiz constants
  @context_type "article_quiz"
  @initial_quiz_message "Start the quiz"
  @max_content_length 12_000

  @doc """
  Creates a new quiz attempt for a user and article.

  Returns `{:ok, attempt}` on success or `{:error, changeset}` on validation failure.
  """
  def create_attempt(user_id, article_id, attrs \\ %{}) do
    now = DateTime.utc_now()

    base_attrs = build_attempt_attrs(user_id, article_id, %{})

    attrs =
      attrs
      |> Map.put_new(:started_at, now)
      |> Map.put_new(:completed_at, now)
      |> Map.merge(base_attrs)

    %ArticleQuizAttempt{}
    |> ArticleQuizAttempt.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a skip attempt (user finished article without taking quiz).

  Returns `{:ok, attempt}` on success or `{:error, changeset}` on validation failure.
  """
  def create_skip_attempt(user_id, article_id) do
    base_attrs = build_attempt_attrs(user_id, article_id, %{})

    attrs =
      base_attrs
      |> Map.put(:score, nil)
      |> Map.put(:max_score, nil)
      |> Map.put(:chat_session_id, nil)
      |> Map.put(:completed_at, DateTime.utc_now())

    %ArticleQuizAttempt{}
    |> ArticleQuizAttempt.changeset(attrs)
    |> Repo.insert()
  end

  # Shared helper to build base attempt attributes
  defp build_attempt_attrs(user_id, article_id, overrides) do
    attempt_number = next_attempt_number(user_id, article_id)

    %{
      user_id: user_id,
      article_id: article_id,
      attempt_number: attempt_number
    }
    |> Map.merge(overrides)
  end

  # Calculate the next attempt number for a user/article pair
  defp next_attempt_number(user_id, article_id) do
    count_attempts_for_article(user_id, article_id) + 1
  end

  @doc """
  Lists all quiz attempts for a user and article, ordered by attempt number (newest first).

  Returns an empty list if no attempts exist.
  """
  def list_attempts_for_article(user_id, article_id) do
    ArticleQuizAttempt
    |> where([a], a.user_id == ^user_id and a.article_id == ^article_id)
    |> order_by([a], desc: a.attempt_number)
    |> Repo.all()
  end

  @doc """
  Gets the best (highest scoring) attempt for a user and article.

  Returns `nil` if no scored attempts exist.
  """
  def best_attempt_for_article(user_id, article_id) do
    ArticleQuizAttempt
    |> where([a], a.user_id == ^user_id and a.article_id == ^article_id)
    |> where([a], not is_nil(a.score))
    |> order_by([a], desc: a.score, desc: a.completed_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Counts the total number of quiz attempts for a user and article.

  Returns 0 if no attempts exist.
  """
  def count_attempts_for_article(user_id, article_id) do
    ArticleQuizAttempt
    |> where([a], a.user_id == ^user_id and a.article_id == ^article_id)
    |> select([a], count(a.id))
    |> Repo.one()
  end

  @doc """
  Gets the latest attempt for a user and article, regardless of score.

  Returns `nil` if no attempts exist.
  """
  def latest_attempt_for_article(user_id, article_id) do
    ArticleQuizAttempt
    |> where([a], a.user_id == ^user_id and a.article_id == ^article_id)
    |> order_by([a], desc: a.attempt_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the best attempts for multiple articles in a single query.

  Returns a list of attempts, one per article (the best scored attempt for each).
  """
  def best_attempts_for_articles(user_id, article_ids) when is_list(article_ids) do
    if Enum.empty?(article_ids) do
      []
    else
      ArticleQuizAttempt
      |> where([a], a.user_id == ^user_id and a.article_id in ^article_ids)
      |> where([a], not is_nil(a.score))
      |> distinct([a], a.article_id)
      |> order_by([a], desc: a.score, desc: a.completed_at)
      |> Repo.all()
    end
  end

  @doc """
  Gets attempt statistics for a user and article.

  Returns a map with:
  - `total_attempts`: Total number of attempts
  - `scored_attempts`: Number of attempts with scores
  - `best_score`: Best score achieved (nil if none)
  - `average_score`: Average score (nil if none)
  """
  def attempt_stats_for_article(user_id, article_id) do
    # Get total attempts count
    total = count_attempts_for_article(user_id, article_id)

    # Get stats for scored attempts in a single query
    scored_stats =
      ArticleQuizAttempt
      |> where([a], a.user_id == ^user_id and a.article_id == ^article_id)
      |> where([a], not is_nil(a.score))
      |> select([a], %{
        count: count(a.id),
        best_score: max(a.score),
        avg_score: avg(a.score)
      })
      |> Repo.one()

    case scored_stats do
      %{count: 0} ->
        %{
          total_attempts: total,
          scored_attempts: 0,
          best_score: nil,
          average_score: nil
        }

      stats ->
        avg_score =
          if stats.avg_score do
            Decimal.to_float(stats.avg_score) |> Float.round(2)
          else
            nil
          end

        %{
          total_attempts: total,
          scored_attempts: stats.count,
          best_score: stats.best_score,
          average_score: avg_score
        }
    end
  end

  # Constants accessors
  def context_type, do: @context_type
  def initial_quiz_message, do: @initial_quiz_message
  def max_content_length, do: @max_content_length
end

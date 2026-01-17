defmodule Langler.QuizzesTest do
  use Langler.DataCase, async: true

  alias Langler.AccountsFixtures
  alias Langler.Content
  alias Langler.Quizzes
  alias Langler.Quizzes.ArticleQuizAttempt

  setup do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Test Article",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    Content.ensure_article_user(article, user.id)

    %{user: user, article: article}
  end

  defp quiz_result(score, max_score, questions \\ []) do
    %{"score" => score, "max_score" => max_score, "questions" => questions}
  end

  describe "create_attempt/3" do
    test "creates attempt with correct attempt_number", %{user: user, article: article} do
      attrs = %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      }

      assert {:ok, attempt1} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt1.attempt_number == 1

      assert {:ok, attempt2} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt2.attempt_number == 2

      assert {:ok, attempt3} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt3.attempt_number == 3
    end

    test "sets timestamps if not provided", %{user: user, article: article} do
      attrs = %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt.started_at != nil
      assert attempt.completed_at != nil
    end

    test "returns error for invalid data", %{user: user, article: article} do
      attrs = %{
        score: -1,
        max_score: 5
      }

      assert {:error, changeset} = Quizzes.create_attempt(user.id, article.id, attrs)
      refute changeset.valid?
    end

    test "validates attempt_number > 0" do
      attrs = %{
        user_id: 1,
        article_id: 1,
        attempt_number: 0,
        score: 4,
        max_score: 5
      }

      changeset = ArticleQuizAttempt.changeset(%ArticleQuizAttempt{}, attrs)
      refute changeset.valid?
    end
  end

  describe "create_skip_attempt/2" do
    test "creates attempt with nil scores", %{user: user, article: article} do
      assert {:ok, attempt} = Quizzes.create_skip_attempt(user.id, article.id)
      assert attempt.score == nil
      assert attempt.max_score == nil
      assert attempt.chat_session_id == nil
      assert attempt.completed_at != nil
      assert attempt.attempt_number == 1
    end

    test "increments attempt_number correctly", %{user: user, article: article} do
      Quizzes.create_skip_attempt(user.id, article.id)

      assert {:ok, attempt2} = Quizzes.create_skip_attempt(user.id, article.id)
      assert attempt2.attempt_number == 2
    end
  end

  describe "list_attempts_for_article/2" do
    test "returns all attempts ordered by attempt_number DESC", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 5,
        max_score: 5,
        result_json: quiz_result(5, 5)
      })

      attempts = Quizzes.list_attempts_for_article(user.id, article.id)
      assert length(attempts) == 3
      assert Enum.at(attempts, 0).attempt_number == 3
      assert Enum.at(attempts, 1).attempt_number == 2
      assert Enum.at(attempts, 2).attempt_number == 1
    end

    test "returns empty list when no attempts", %{user: user, article: article} do
      assert Quizzes.list_attempts_for_article(user.id, article.id) == []
    end
  end

  describe "best_attempt_for_article/2" do
    test "returns highest score attempt", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 5,
        max_score: 5,
        result_json: quiz_result(5, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      best = Quizzes.best_attempt_for_article(user.id, article.id)
      assert best.score == 5
    end

    test "ignores nil scores", %{user: user, article: article} do
      Quizzes.create_skip_attempt(user.id, article.id)

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      best = Quizzes.best_attempt_for_article(user.id, article.id)
      assert best.score == 4
    end

    test "returns nil when no scored attempts", %{user: user, article: article} do
      Quizzes.create_skip_attempt(user.id, article.id)

      assert Quizzes.best_attempt_for_article(user.id, article.id) == nil
    end

    test "returns nil when no attempts", %{user: user, article: article} do
      assert Quizzes.best_attempt_for_article(user.id, article.id) == nil
    end

    test "handles tie by returning most recent", %{user: user, article: article} do
      # Create two attempts with same score
      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        completed_at: ~U[2024-01-01 12:00:00Z]
      })

      Process.sleep(10)

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        completed_at: ~U[2024-01-01 13:00:00Z]
      })

      best = Quizzes.best_attempt_for_article(user.id, article.id)
      assert best.score == 4
      # Should return the most recent one (higher completed_at)
      assert DateTime.compare(best.completed_at, ~U[2024-01-01 12:00:00Z]) == :gt
    end
  end

  describe "count_attempts_for_article/2" do
    test "returns correct count", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      Quizzes.create_skip_attempt(user.id, article.id)

      assert Quizzes.count_attempts_for_article(user.id, article.id) == 3
    end

    test "returns 0 when no attempts", %{user: user, article: article} do
      assert Quizzes.count_attempts_for_article(user.id, article.id) == 0
    end
  end

  describe "ArticleQuizAttempt changeset" do
    test "validates required fields" do
      changeset = ArticleQuizAttempt.changeset(%ArticleQuizAttempt{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).article_id
      assert "can't be blank" in errors_on(changeset).attempt_number
    end

    test "allows nullable score fields", %{user: user, article: article} do
      changeset =
        ArticleQuizAttempt.changeset(%ArticleQuizAttempt{}, %{
          user_id: user.id,
          article_id: article.id,
          attempt_number: 1,
          score: nil,
          max_score: nil
        })

      assert changeset.valid?
    end

    test "validates score >= 0 when present", %{user: user, article: article} do
      changeset =
        ArticleQuizAttempt.changeset(%ArticleQuizAttempt{}, %{
          user_id: user.id,
          article_id: article.id,
          attempt_number: 1,
          score: -1
        })

      refute changeset.valid?
    end

    test "validates max_score > 0 when present", %{user: user, article: article} do
      changeset =
        ArticleQuizAttempt.changeset(%ArticleQuizAttempt{}, %{
          user_id: user.id,
          article_id: article.id,
          attempt_number: 1,
          max_score: 0
        })

      refute changeset.valid?
    end

    test "handles score > max_score gracefully", %{user: user, article: article} do
      attrs = %{
        score: 10,
        max_score: 5,
        result_json: quiz_result(10, 5)
      }

      assert {:error, changeset} = Quizzes.create_attempt(user.id, article.id, attrs)
      refute changeset.valid?
    end

    test "handles very large result_json", %{user: user, article: article} do
      questions =
        for i <- 1..100 do
          %{
            "question" => "Question #{i}",
            "user_answer" => "Answer #{i}",
            "correct" => true,
            "explanation" => String.duplicate("Explanation ", 100)
          }
        end

      attrs = %{
        score: 100,
        max_score: 100,
        result_json: quiz_result(100, 100, questions)
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert length(attempt.result_json["questions"]) == 100
    end

    test "handles missing chat_session_id", %{user: user, article: article} do
      attrs = %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        chat_session_id: nil
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt.chat_session_id == nil
    end

    test "handles custom started_at and completed_at", %{user: user, article: article} do
      started = ~U[2024-01-01 10:00:00Z]
      completed = ~U[2024-01-01 10:15:00Z]

      attrs = %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        started_at: started,
        completed_at: completed
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt.started_at == started
      assert attempt.completed_at == completed
    end
  end

  describe "edge cases" do
    test "handles multiple users with same article", %{article: article} do
      user1 = AccountsFixtures.user_fixture()
      user2 = AccountsFixtures.user_fixture()

      Content.ensure_article_user(article, user1.id)
      Content.ensure_article_user(article, user2.id)

      Quizzes.create_attempt(user1.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      Quizzes.create_attempt(user2.id, article.id, %{
        score: 5,
        max_score: 5,
        result_json: quiz_result(5, 5)
      })

      assert Quizzes.count_attempts_for_article(user1.id, article.id) == 1
      assert Quizzes.count_attempts_for_article(user2.id, article.id) == 1

      best1 = Quizzes.best_attempt_for_article(user1.id, article.id)
      best2 = Quizzes.best_attempt_for_article(user2.id, article.id)

      assert best1.score == 3
      assert best2.score == 5
    end

    test "handles non-existent article_id gracefully", %{user: user} do
      non_existent_id = 999_999

      assert Quizzes.list_attempts_for_article(user.id, non_existent_id) == []
      assert Quizzes.best_attempt_for_article(user.id, non_existent_id) == nil
      assert Quizzes.count_attempts_for_article(user.id, non_existent_id) == 0
    end

    test "handles non-existent user_id gracefully", %{article: article} do
      non_existent_id = 999_999

      assert Quizzes.list_attempts_for_article(non_existent_id, article.id) == []
      assert Quizzes.best_attempt_for_article(non_existent_id, article.id) == nil
      assert Quizzes.count_attempts_for_article(non_existent_id, article.id) == 0
    end

    test "handles score of 0", %{user: user, article: article} do
      attrs = %{
        score: 0,
        max_score: 5,
        result_json: quiz_result(0, 5)
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt.score == 0

      best = Quizzes.best_attempt_for_article(user.id, article.id)
      assert best.score == 0
    end

    test "handles empty questions array", %{user: user, article: article} do
      attrs = %{
        score: 0,
        max_score: 5,
        result_json: quiz_result(0, 5)
      }

      assert {:ok, attempt} = Quizzes.create_attempt(user.id, article.id, attrs)
      assert attempt.result_json["questions"] == []
    end

    test "handles very high attempt numbers", %{user: user, article: article} do
      # Create many attempts to test high attempt numbers
      for i <- 1..50 do
        Quizzes.create_attempt(user.id, article.id, %{
          score: i,
          max_score: 50,
          result_json: quiz_result(i, 50)
        })
      end

      attempts = Quizzes.list_attempts_for_article(user.id, article.id)
      assert length(attempts) == 50
      assert hd(attempts).attempt_number == 50
    end
  end

  describe "latest_attempt_for_article/2" do
    test "returns most recent attempt", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5),
        completed_at: ~U[2024-01-01 10:00:00Z]
      })

      Process.sleep(10)

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5),
        completed_at: ~U[2024-01-01 11:00:00Z]
      })

      latest = Quizzes.latest_attempt_for_article(user.id, article.id)
      assert latest.attempt_number == 2
      assert latest.score == 4
    end

    test "returns nil when no attempts", %{user: user, article: article} do
      assert Quizzes.latest_attempt_for_article(user.id, article.id) == nil
    end

    test "returns latest even if it's a skip attempt", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 5,
        max_score: 5,
        result_json: quiz_result(5, 5)
      })

      Quizzes.create_skip_attempt(user.id, article.id)

      latest = Quizzes.latest_attempt_for_article(user.id, article.id)
      assert latest.attempt_number == 2
      assert latest.score == nil
    end
  end

  describe "attempt_stats_for_article/2" do
    test "returns stats with scores", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 5,
        max_score: 5,
        result_json: quiz_result(5, 5)
      })

      Quizzes.create_skip_attempt(user.id, article.id)

      stats = Quizzes.attempt_stats_for_article(user.id, article.id)

      assert stats.total_attempts == 4
      assert stats.scored_attempts == 3
      assert stats.best_score == 5
      assert stats.average_score == 4.0
    end

    test "returns stats with no scores", %{user: user, article: article} do
      Quizzes.create_skip_attempt(user.id, article.id)
      Quizzes.create_skip_attempt(user.id, article.id)

      stats = Quizzes.attempt_stats_for_article(user.id, article.id)

      assert stats.total_attempts == 2
      assert stats.scored_attempts == 0
      assert stats.best_score == nil
      assert stats.average_score == nil
    end

    test "returns empty stats when no attempts", %{user: user, article: article} do
      stats = Quizzes.attempt_stats_for_article(user.id, article.id)

      assert stats.total_attempts == 0
      assert stats.scored_attempts == 0
      assert stats.best_score == nil
      assert stats.average_score == nil
    end

    test "calculates average correctly with different scores", %{user: user, article: article} do
      Quizzes.create_attempt(user.id, article.id, %{
        score: 2,
        max_score: 5,
        result_json: quiz_result(2, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 4,
        max_score: 5,
        result_json: quiz_result(4, 5)
      })

      Quizzes.create_attempt(user.id, article.id, %{
        score: 3,
        max_score: 5,
        result_json: quiz_result(3, 5)
      })

      stats = Quizzes.attempt_stats_for_article(user.id, article.id)

      assert stats.average_score == 3.0
    end
  end
end

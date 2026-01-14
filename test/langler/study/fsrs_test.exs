defmodule Langler.Study.FSRSTest do
  use ExUnit.Case, async: true

  alias Langler.Study.FSRS

  describe "calculate_next_review/3" do
    test "advances through learning steps before review" do
      item =
        FSRS.item(%{
          user_id: 1,
          word_id: 2,
          state: :learning,
          step: 0
        })

      now = DateTime.utc_now()
      result = FSRS.calculate_next_review(item, :good, now: now)

      assert result.state in [:learning, :review]
      assert result.due
      assert DateTime.compare(result.due, now) == :gt
    end

    test "updates stability, interval, and ease during reviews" do
      now = DateTime.utc_now()

      item =
        FSRS.item(%{
          user_id: 1,
          word_id: 2,
          state: :review,
          stability: 3.0,
          difficulty: 5.0,
          ease_factor: 2.4,
          last_reviewed_at: DateTime.add(now, -86_400, :second),
          due_date: DateTime.add(now, -3600, :second)
        })

      result = FSRS.calculate_next_review(item, :easy, now: now)

      assert result.state == :review
      assert result.interval >= 1
      assert result.ease_factor > 2.4
      assert result.stability > 3.0
      assert DateTime.compare(result.due, now) == :gt
    end
  end

  describe "update_ease_factor/2" do
    test "clamps ease factor between 1.3 and 3.7" do
      assert FSRS.update_ease_factor(1.3, :again) == 1.3
      assert FSRS.update_ease_factor(3.7, :easy) == 3.7
    end
  end
end

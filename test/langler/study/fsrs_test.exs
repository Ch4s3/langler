defmodule Langler.Study.FSRSTest do
  use ExUnit.Case, async: true

  alias Langler.Study.FSRS

  describe "params/1" do
    setup do
      original = Application.get_env(:langler, Langler.Study.FSRS.Params)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:langler, Langler.Study.FSRS.Params)
          _ -> Application.put_env(:langler, Langler.Study.FSRS.Params, original)
        end
      end)

      :ok
    end

    test "merges config and overrides" do
      Application.put_env(:langler, Langler.Study.FSRS.Params, %{
        desired_retention: 0.8,
        learning_steps: [5.0],
        weights: [1.0, 2.0]
      })

      params = FSRS.params(enable_fuzzing: false, learning_steps: [2.0, 4.0])

      assert params.desired_retention == 0.8
      assert params.learning_steps == [2.0, 4.0]
      assert params.enable_fuzzing == false
      assert params.weights == [1.0, 2.0]
    end
  end

  describe "item/2" do
    test "applies overrides for known fields" do
      item =
        FSRS.item(
          %{
            user_id: 1,
            word_id: 2,
            state: :learning,
            difficulty: 3.0
          },
          difficulty: 7.5,
          state: :review,
          unknown: :value
        )

      assert item.difficulty == 7.5
      assert item.state == :review
      refute Map.has_key?(item, :unknown)
    end
  end

  describe "quality_from_rating/1 and rating_from_quality/1" do
    test "maps ratings and qualities consistently" do
      assert FSRS.quality_from_rating(:again) == 0
      assert FSRS.quality_from_rating(:hard) == 2
      assert FSRS.quality_from_rating(:good) == 3
      assert FSRS.quality_from_rating(:easy) == 4

      assert FSRS.rating_from_quality(0) == :again
      assert FSRS.rating_from_quality(1) == :hard
      assert FSRS.rating_from_quality(2) == :hard
      assert FSRS.rating_from_quality(3) == :good
      assert FSRS.rating_from_quality(4) == :easy
    end
  end

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

    test "schedules relearning on a failed review" do
      now = DateTime.utc_now()

      item =
        FSRS.item(%{
          user_id: 1,
          word_id: 2,
          state: :review,
          stability: 3.0,
          difficulty: 4.0,
          ease_factor: 2.5,
          last_reviewed_at: DateTime.add(now, -86_400, :second),
          due_date: DateTime.add(now, -3600, :second)
        })

      result = FSRS.calculate_next_review(item, :again, now: now)

      assert result.state == :relearning
      assert result.step == 0
      assert result.interval == 0
      assert result.stability <= item.stability
      assert result.ease_factor <= item.ease_factor
      assert DateTime.compare(result.due, now) == :gt
    end

    test "starts review when learning step is complete" do
      now = DateTime.utc_now()

      item =
        FSRS.item(%{
          user_id: 1,
          word_id: 2,
          state: :learning,
          step: 1
        })

      result = FSRS.calculate_next_review(item, :easy, now: now)

      assert result.state == :review
      assert result.step == nil
      assert result.interval >= 1
      assert DateTime.compare(result.due, now) == :gt
    end
  end

  describe "calculate_interval/3" do
    test "handles edge cases and rating adjustments" do
      assert FSRS.calculate_interval(0, 2.5, :again) == 1
      assert FSRS.calculate_interval(-3, 2.5, :good) == 1
      assert FSRS.calculate_interval(1, 2.5, :good) == 6
      assert FSRS.calculate_interval(10, 2.0, :hard) == 16
      assert FSRS.calculate_interval(10, 2.0, :easy) == 26
    end
  end

  describe "update_ease_factor/2" do
    test "clamps ease factor between 1.3 and 3.7" do
      assert FSRS.update_ease_factor(1.3, :again) == 1.3
      assert FSRS.update_ease_factor(3.7, :easy) == 3.7
    end

    test "applies rating deltas" do
      assert FSRS.update_ease_factor(2.5, :again) == 2.15
      assert FSRS.update_ease_factor(2.5, :hard) == 2.35
      assert FSRS.update_ease_factor(2.5, :good) == 2.5
      assert FSRS.update_ease_factor(2.5, :easy) == 2.65
    end
  end
end

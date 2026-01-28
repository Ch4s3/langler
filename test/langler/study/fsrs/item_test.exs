defmodule Langler.Study.FSRS.ItemTest do
  use ExUnit.Case, async: true

  alias Langler.Study.FSRS.Item

  describe "from_record/1" do
    test "builds item from record with required fields" do
      record = %{
        user_id: 1,
        word_id: 2
      }

      item = Item.from_record(record)

      assert item.user_id == 1
      assert item.word_id == 2
      assert item.state == :learning
    end

    test "includes all optional fields when present" do
      record = %{
        user_id: 1,
        word_id: 2,
        stability: 3.5,
        difficulty: 5.0,
        retrievability: 0.85,
        elapsed_days: 10,
        last_quality: 3,
        interval: 7,
        ease_factor: 2.5,
        state: :review,
        step: 2,
        due_date: ~U[2024-01-15 10:00:00Z],
        last_reviewed_at: ~U[2024-01-10 10:00:00Z]
      }

      item = Item.from_record(record)

      assert item.stability == 3.5
      assert item.difficulty == 5.0
      assert item.retrievability == 0.85
      assert item.elapsed_days == 10
      assert item.last_quality == 3
      assert item.interval == 7
      assert item.ease_factor == 2.5
      assert item.state == :review
      assert item.step == 2
      assert item.due == ~U[2024-01-15 10:00:00Z]
      assert item.last_reviewed_at == ~U[2024-01-10 10:00:00Z]
    end

    test "normalizes state from string to atom" do
      assert Item.from_record(%{user_id: 1, word_id: 2, state: "learning"}).state == :learning
      assert Item.from_record(%{user_id: 1, word_id: 2, state: "review"}).state == :review
      assert Item.from_record(%{user_id: 1, word_id: 2, state: "relearning"}).state == :relearning
    end

    test "normalizes state from atom" do
      assert Item.from_record(%{user_id: 1, word_id: 2, state: :learning}).state == :learning
      assert Item.from_record(%{user_id: 1, word_id: 2, state: :review}).state == :review
      assert Item.from_record(%{user_id: 1, word_id: 2, state: :relearning}).state == :relearning
    end

    test "handles invalid state values" do
      assert Item.from_record(%{user_id: 1, word_id: 2, state: "invalid"}).state == nil
      assert Item.from_record(%{user_id: 1, word_id: 2, state: :invalid}).state == nil
      assert Item.from_record(%{user_id: 1, word_id: 2, state: nil}).state == nil
    end

    test "prioritizes due_date over due field" do
      record = %{
        user_id: 1,
        word_id: 2,
        due_date: ~U[2024-01-15 10:00:00Z],
        due: ~U[2024-01-20 10:00:00Z]
      }

      item = Item.from_record(record)
      assert item.due == ~U[2024-01-15 10:00:00Z]
    end

    test "falls back to due field when due_date is missing" do
      record = %{
        user_id: 1,
        word_id: 2,
        due: ~U[2024-01-20 10:00:00Z]
      }

      item = Item.from_record(record)
      assert item.due == ~U[2024-01-20 10:00:00Z]
    end
  end

  describe "elapsed_days/2" do
    test "returns 0 when last_reviewed_at is nil" do
      item = %Item{user_id: 1, word_id: 2, last_reviewed_at: nil}
      {updated_item, elapsed} = Item.elapsed_days(item)

      assert elapsed == 0
      assert updated_item == item
    end

    test "calculates elapsed days from last review" do
      now = ~U[2024-01-15 10:00:00Z]
      last_reviewed = ~U[2024-01-10 10:00:00Z]
      item = %Item{user_id: 1, word_id: 2, last_reviewed_at: last_reviewed}

      {updated_item, elapsed} = Item.elapsed_days(item, now)

      assert elapsed == 5
      assert updated_item.elapsed_days == 5
    end

    test "returns 0 for negative time differences" do
      now = ~U[2024-01-10 10:00:00Z]
      last_reviewed = ~U[2024-01-15 10:00:00Z]
      item = %Item{user_id: 1, word_id: 2, last_reviewed_at: last_reviewed}

      {updated_item, elapsed} = Item.elapsed_days(item, now)

      assert elapsed == 0
      assert updated_item.elapsed_days == 0
    end

    test "uses cached value if already set" do
      item = %Item{
        user_id: 1,
        word_id: 2,
        elapsed_days: 10,
        last_reviewed_at: ~U[2024-01-01 10:00:00Z]
      }

      now = ~U[2024-01-15 10:00:00Z]

      {updated_item, elapsed} = Item.elapsed_days(item, now)

      # Should recalculate and update
      assert elapsed == 14
      assert updated_item.elapsed_days == 14
    end
  end

  describe "retrievability/2" do
    test "returns 0.0 when stability is nil" do
      item = %Item{user_id: 1, word_id: 2, stability: nil}
      {updated_item, retrievability} = Item.retrievability(item)

      assert retrievability == 0.0
      assert updated_item.retrievability == 0.0
    end

    test "returns 0.99 when elapsed days is 0" do
      now = ~U[2024-01-15 10:00:00Z]
      item = %Item{user_id: 1, word_id: 2, stability: 5.0, last_reviewed_at: now}

      {updated_item, retrievability} = Item.retrievability(item, now)

      assert retrievability == 0.99
      assert updated_item.retrievability == 0.99
    end

    test "calculates retrievability with positive elapsed days" do
      now = ~U[2024-01-15 10:00:00Z]
      last_reviewed = ~U[2024-01-10 10:00:00Z]
      item = %Item{user_id: 1, word_id: 2, stability: 5.0, last_reviewed_at: last_reviewed}

      {updated_item, retrievability} = Item.retrievability(item, now)

      assert retrievability > 0.0
      assert retrievability < 1.0
      assert updated_item.retrievability == retrievability
    end

    test "retrievability decreases as elapsed days increase" do
      item = %Item{
        user_id: 1,
        word_id: 2,
        stability: 5.0,
        last_reviewed_at: ~U[2024-01-10 10:00:00Z]
      }

      {_item1, r1} = Item.retrievability(item, ~U[2024-01-11 10:00:00Z])
      {_item2, r2} = Item.retrievability(item, ~U[2024-01-15 10:00:00Z])
      {_item3, r3} = Item.retrievability(item, ~U[2024-01-20 10:00:00Z])

      assert r1 > r2
      assert r2 > r3
    end

    test "caches retrievability and elapsed_days" do
      now = ~U[2024-01-15 10:00:00Z]
      last_reviewed = ~U[2024-01-10 10:00:00Z]
      item = %Item{user_id: 1, word_id: 2, stability: 5.0, last_reviewed_at: last_reviewed}

      {updated_item, _retrievability} = Item.retrievability(item, now)

      assert updated_item.elapsed_days == 5
      assert is_float(updated_item.retrievability)
    end
  end
end

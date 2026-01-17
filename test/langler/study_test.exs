defmodule Langler.StudyTest do
  use Langler.DataCase, async: true

  alias Langler.AccountsFixtures
  alias Langler.Study
  alias Langler.StudyFixtures
  alias Langler.VocabularyFixtures

  test "create_item/1 persists FSRS item" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()

    assert {:ok, item} =
             Study.create_item(%{
               user_id: user.id,
               word_id: word.id,
               ease_factor: 2.5
             })

    assert item.user_id == user.id
  end

  test "due_items/2 filters by due date" do
    item =
      StudyFixtures.fsrs_item_fixture(%{due_date: DateTime.add(DateTime.utc_now(), -60, :second)})

    assert [_] = Study.due_items(item.user_id, DateTime.utc_now())
  end

  test "to_scheduler_item/1 converts to FSRS struct" do
    item = StudyFixtures.fsrs_item_fixture()
    scheduler_item = Study.to_scheduler_item(item)

    assert scheduler_item.user_id == item.user_id
  end

  test "review_item/2 updates interval and history" do
    now = DateTime.utc_now()

    item =
      StudyFixtures.fsrs_item_fixture(%{
        interval: 1,
        due_date: DateTime.add(now, -86_400, :second),
        ease_factor: 2.5
      })

    assert {:ok, updated} = Study.review_item(item, :good, now: now)
    assert updated.interval >= 0
    assert List.last(updated.quality_history) == 3
    assert DateTime.compare(updated.due_date, now) == :gt
  end

  test "list_items_for_user/2 returns items for user" do
    user = AccountsFixtures.user_fixture()
    word1 = VocabularyFixtures.word_fixture()
    word2 = VocabularyFixtures.word_fixture()

    item1 = StudyFixtures.fsrs_item_fixture(%{user: user, word: word1})
    item2 = StudyFixtures.fsrs_item_fixture(%{user: user, word: word2})

    items = Study.list_items_for_user(user.id)
    item_ids = Enum.map(items, & &1.id)

    assert item1.id in item_ids
    assert item2.id in item_ids
  end

  test "list_items_for_user/2 filters by word_ids" do
    user = AccountsFixtures.user_fixture()
    word1 = VocabularyFixtures.word_fixture()
    word2 = VocabularyFixtures.word_fixture()

    item1 = StudyFixtures.fsrs_item_fixture(%{user: user, word: word1})
    _item2 = StudyFixtures.fsrs_item_fixture(%{user: user, word: word2})

    items = Study.list_items_for_user(user.id, word_ids: [word1.id])
    assert length(items) == 1
    assert hd(items).id == item1.id
  end

  test "get_practice_words/2 returns words due for practice" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()

    StudyFixtures.fsrs_item_fixture(%{
      user: user,
      word: word,
      due_date: DateTime.add(DateTime.utc_now(), -60, :second)
    })

    words = Study.get_practice_words(user.id)
    assert word.normalized_form in words
  end

  test "get_practice_words/2 returns words not marked easy" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()

    StudyFixtures.fsrs_item_fixture(%{
      user: user,
      word: word,
      quality_history: [2, 3]
    })

    words = Study.get_practice_words(user.id)
    assert word.normalized_form in words
  end

  test "get_item!/1 returns item by id" do
    item = StudyFixtures.fsrs_item_fixture()
    found = Study.get_item!(item.id)
    assert found.id == item.id
  end

  test "get_item_by_user_and_word/2 returns item" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()
    item = StudyFixtures.fsrs_item_fixture(%{user: user, word: word})

    found = Study.get_item_by_user_and_word(user.id, word.id)
    assert found.id == item.id
  end

  test "schedule_new_item/2 creates new item" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()

    assert {:ok, item} = Study.schedule_new_item(user.id, word.id)
    assert item.user_id == user.id
    assert item.word_id == word.id
  end

  test "schedule_new_item/2 returns existing item" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()
    existing = StudyFixtures.fsrs_item_fixture(%{user: user, word: word})

    assert {:ok, item} = Study.schedule_new_item(user.id, word.id)
    assert item.id == existing.id
  end

  test "remove_item/2 deletes item" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()
    item = StudyFixtures.fsrs_item_fixture(%{user: user, word: word})

    assert {:ok, _} = Study.remove_item(user.id, word.id)

    assert_raise Ecto.NoResultsError, fn ->
      Study.get_item!(item.id)
    end
  end

  test "remove_item/2 returns error when not found" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture()

    assert {:error, :not_found} = Study.remove_item(user.id, word.id)
  end

  test "update_item/2 updates item" do
    item = StudyFixtures.fsrs_item_fixture()

    assert {:ok, updated} = Study.update_item(item, %{ease_factor: 2.8})
    assert updated.ease_factor == 2.8
  end

  test "append_quality/3 adds quality to history" do
    item = StudyFixtures.fsrs_item_fixture(%{quality_history: [3, 2]})

    assert {:ok, updated} = Study.append_quality(item, 4)
    assert List.last(updated.quality_history) == 4
    assert length(updated.quality_history) == 3
  end

  test "append_quality/3 with attrs updates item" do
    item = StudyFixtures.fsrs_item_fixture()

    assert {:ok, updated} = Study.append_quality(item, 3, %{ease_factor: 2.6})
    assert List.last(updated.quality_history) == 3
    assert updated.ease_factor == 2.6
  end

  test "get_user_vocabulary_level/1 returns level" do
    user = AccountsFixtures.user_fixture()
    word = VocabularyFixtures.word_fixture(%{frequency_rank: 1000})
    StudyFixtures.fsrs_item_fixture(%{user: user, word: word})

    level = Study.get_user_vocabulary_level(user.id)
    assert Map.has_key?(level, :cefr_level)
    assert Map.has_key?(level, :numeric_level)
  end

  test "review_item/2 normalizes string ratings" do
    item = StudyFixtures.fsrs_item_fixture()

    assert {:ok, _} = Study.review_item(item, "good")
    assert {:ok, _} = Study.review_item(item, "hard")
    assert {:ok, _} = Study.review_item(item, "easy")
    assert {:ok, _} = Study.review_item(item, "again")
  end
end

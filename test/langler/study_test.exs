defmodule Langler.StudyTest do
  use Langler.DataCase, async: true

  alias Langler.Study
  alias Langler.StudyFixtures
  alias Langler.AccountsFixtures
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
end

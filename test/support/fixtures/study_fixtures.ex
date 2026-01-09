defmodule Langler.StudyFixtures do
  alias Langler.Study
  alias Langler.AccountsFixtures
  alias Langler.VocabularyFixtures

  def fsrs_item_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || AccountsFixtures.user_fixture()
    word = Map.get(attrs, :word) || VocabularyFixtures.word_fixture()

    {:ok, item} =
      attrs
      |> Enum.into(%{
        user_id: user.id,
        word_id: word.id,
        ease_factor: 2.5,
        interval: 0,
        repetitions: 0,
        state: "learning"
      })
      |> Study.create_item()

    item
  end
end

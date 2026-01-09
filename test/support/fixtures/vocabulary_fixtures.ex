defmodule Langler.VocabularyFixtures do
  alias Langler.Vocabulary
  alias Langler.ContentFixtures

  def word_fixture(attrs \\ %{}) do
    {:ok, word} =
      attrs
      |> Enum.into(%{
        normalized_form: "hola",
        lemma: "hola",
        language: "spanish",
        part_of_speech: "interjection"
      })
      |> Vocabulary.create_word()

    word
  end

  def occurrence_fixture(attrs \\ %{}) do
    sentence = Map.get(attrs, :sentence) || ContentFixtures.sentence_fixture()
    word = Map.get(attrs, :word) || word_fixture()

    {:ok, occurrence} =
      attrs
      |> Enum.into(%{
        position: 0,
        context: sentence.content,
        sentence_id: sentence.id,
        word_id: word.id
      })
      |> Vocabulary.create_occurrence()

    occurrence
  end
end

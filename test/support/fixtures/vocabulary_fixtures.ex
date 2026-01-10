defmodule Langler.VocabularyFixtures do
  @moduledoc false

  alias Langler.ContentFixtures
  alias Langler.Vocabulary

  def word_fixture(attrs \\ %{}) do
    unique_term = "hola-#{System.unique_integer([:positive])}"

    {:ok, word} =
      attrs
      |> Enum.into(%{
        normalized_form: unique_term,
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

defmodule Langler.Vocabulary.WordOccurrence do
  @moduledoc """
  Ecto schema for word occurrences in articles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "word_occurrences" do
    field :position, :integer
    field :context, :string

    belongs_to :word, Langler.Vocabulary.Word
    belongs_to :sentence, Langler.Content.Sentence

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [:position, :context, :word_id, :sentence_id])
    |> validate_required([:position, :word_id, :sentence_id])
    |> assoc_constraint(:word)
    |> assoc_constraint(:sentence)
  end
end

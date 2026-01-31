defmodule Langler.Vocabulary.IdiomOccurrence do
  @moduledoc """
  Ecto schema for idiom occurrences in article sentences.

  Tracks where multi-word idioms appear, with start/end token positions
  so the reader can highlight and make them clickable as a single span.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "idiom_occurrences" do
    field :start_position, :integer
    field :end_position, :integer

    belongs_to :word, Langler.Vocabulary.Word
    belongs_to :sentence, Langler.Content.Sentence

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [:start_position, :end_position, :word_id, :sentence_id])
    |> validate_required([:start_position, :end_position, :word_id, :sentence_id])
    |> validate_number(:start_position, greater_than_or_equal_to: 0)
    |> validate_number(:end_position, greater_than_or_equal_to: 0)
    |> validate_span_order()
    |> assoc_constraint(:word)
    |> assoc_constraint(:sentence)
    |> unique_constraint([:sentence_id, :word_id, :start_position, :end_position],
      name: :idiom_occurrences_sentence_word_span_index
    )
  end

  defp validate_span_order(changeset) do
    start_pos = get_field(changeset, :start_position)
    end_pos = get_field(changeset, :end_position)

    if is_integer(start_pos) and is_integer(end_pos) and end_pos < start_pos do
      add_error(changeset, :end_position, "must be >= start_position")
    else
      changeset
    end
  end
end

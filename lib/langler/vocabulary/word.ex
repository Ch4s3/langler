defmodule Langler.Vocabulary.Word do
  use Ecto.Schema
  import Ecto.Changeset

  schema "words" do
    field :normalized_form, :string
    field :lemma, :string
    field :language, :string
    field :part_of_speech, :string

    has_many :occurrences, Langler.Vocabulary.WordOccurrence
    has_many :fsrs_items, Langler.Study.FSRSItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(word, attrs) do
    word
    |> cast(attrs, [:normalized_form, :lemma, :language, :part_of_speech])
    |> validate_required([:normalized_form, :language])
    |> unique_constraint([:normalized_form, :language])
  end
end

defmodule Langler.Vocabulary.Word do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "words" do
    field :normalized_form, :string
    field :lemma, :string
    field :language, :string
    field :part_of_speech, :string
    field :definitions, {:array, :string}, default: []
    field :conjugations, :map

    has_many :occurrences, Langler.Vocabulary.WordOccurrence
    has_many :fsrs_items, Langler.Study.FSRSItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(word, attrs) do
    word
    |> cast(attrs, [:normalized_form, :lemma, :language, :part_of_speech, :definitions, :conjugations])
    |> validate_required([:normalized_form, :language])
    |> put_default_definitions()
    |> unique_constraint([:normalized_form, :language])
  end

  defp put_default_definitions(changeset) do
    case get_field(changeset, :definitions) do
      nil -> put_change(changeset, :definitions, [])
      _ -> changeset
    end
  end
end

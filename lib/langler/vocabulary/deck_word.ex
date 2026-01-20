defmodule Langler.Vocabulary.DeckWord do
  @moduledoc """
  Ecto schema for the join table between decks and words.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Vocabulary.{Deck, Word}

  schema "deck_words" do
    belongs_to :deck, Deck
    belongs_to :word, Word

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_word, attrs) do
    deck_word
    |> cast(attrs, [:deck_id, :word_id])
    |> validate_required([:deck_id, :word_id])
    |> unique_constraint([:deck_id, :word_id])
    |> assoc_constraint(:deck)
    |> assoc_constraint(:word)
  end
end

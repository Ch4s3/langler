defmodule Langler.Vocabulary.DeckCustomCard do
  @moduledoc """
  Ecto schema for the join table between decks and custom cards.

  Allows custom cards to appear in multiple decks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Vocabulary.{CustomCard, Deck}

  schema "deck_custom_cards" do
    belongs_to :deck, Deck
    belongs_to :custom_card, CustomCard

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_custom_card, attrs) do
    deck_custom_card
    |> cast(attrs, [:deck_id, :custom_card_id])
    |> validate_required([:deck_id, :custom_card_id])
    |> unique_constraint([:deck_id, :custom_card_id])
  end
end

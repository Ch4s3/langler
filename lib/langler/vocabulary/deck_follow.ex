defmodule Langler.Vocabulary.DeckFollow do
  @moduledoc """
  Ecto schema for following public decks.

  Allows users to subscribe to public decks at scale.
  Each follow is one row, not one row per word.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Accounts.User
  alias Langler.Vocabulary.Deck

  schema "deck_follows" do
    belongs_to :deck, Deck
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_follow, attrs) do
    deck_follow
    |> cast(attrs, [:deck_id, :user_id])
    |> validate_required([:deck_id, :user_id])
    |> unique_constraint([:deck_id, :user_id])
  end
end

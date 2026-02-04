defmodule Langler.Vocabulary.CustomCard do
  @moduledoc """
  Ecto schema for user-created custom flashcards.

  Custom cards have a front and back (like traditional flashcards)
  and can be added to multiple decks via DeckCustomCard join table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Accounts.User
  alias Langler.Study.FSRSItem
  alias Langler.Vocabulary.{Deck, DeckCustomCard}

  schema "custom_cards" do
    field :front, :string
    field :back, :string
    field :language, :string

    belongs_to :user, User
    has_many :deck_custom_cards, DeckCustomCard
    many_to_many :decks, Deck, join_through: DeckCustomCard
    has_many :fsrs_items, FSRSItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(custom_card, attrs) do
    custom_card
    |> cast(attrs, [:front, :back, :language, :user_id])
    |> validate_required([:front, :back, :language, :user_id])
    |> validate_length(:front, min: 1, max: 1000)
    |> validate_length(:back, min: 1, max: 1000)
  end
end

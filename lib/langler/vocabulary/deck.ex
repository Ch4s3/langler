defmodule Langler.Vocabulary.Deck do
  @moduledoc """
  Ecto schema for vocabulary decks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Accounts.User
  alias Langler.Vocabulary.{CustomCard, DeckCustomCard, DeckFollow, DeckShare, DeckWord, Word}

  schema "decks" do
    field :name, :string
    field :description, :string
    field :visibility, :string, default: "private"
    field :language, :string
    field :is_default, :boolean, default: false

    belongs_to :user, User
    has_many :deck_words, DeckWord
    has_many :deck_custom_cards, DeckCustomCard
    has_many :deck_follows, DeckFollow
    has_many :deck_shares, DeckShare
    many_to_many :words, Word, join_through: DeckWord
    many_to_many :custom_cards, CustomCard, join_through: DeckCustomCard

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck, attrs) do
    deck
    |> cast(attrs, [:name, :description, :visibility, :language, :is_default, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:visibility, ["private", "shared", "public"])
    |> unique_constraint([:user_id, :name])
  end
end

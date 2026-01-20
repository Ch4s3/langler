defmodule Langler.Vocabulary.Deck do
  @moduledoc """
  Ecto schema for vocabulary decks.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Accounts.User
  alias Langler.Vocabulary.{DeckWord, Word}

  schema "decks" do
    field :name, :string
    field :is_default, :boolean, default: false

    belongs_to :user, User
    has_many :deck_words, DeckWord
    many_to_many :words, Word, join_through: DeckWord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck, attrs) do
    deck
    |> cast(attrs, [:name, :is_default, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint([:user_id, :name])
  end
end

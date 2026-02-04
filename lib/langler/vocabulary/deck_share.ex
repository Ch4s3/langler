defmodule Langler.Vocabulary.DeckShare do
  @moduledoc """
  Ecto schema for explicit deck sharing.

  Allows deck owners to share with specific users (small scale, e.g., study buddies).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Accounts.User
  alias Langler.Vocabulary.Deck

  schema "deck_shares" do
    field :permission, :string, default: "view"

    belongs_to :deck, Deck
    belongs_to :shared_with_user, User, foreign_key: :shared_with_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(deck_share, attrs) do
    deck_share
    |> cast(attrs, [:deck_id, :shared_with_user_id, :permission])
    |> validate_required([:deck_id, :shared_with_user_id, :permission])
    |> validate_inclusion(:permission, ["view", "edit"])
    |> unique_constraint([:deck_id, :shared_with_user_id])
  end
end

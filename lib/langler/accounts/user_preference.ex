defmodule Langler.Accounts.UserPreference do
  @moduledoc """
  Ecto schema for user preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Langler.Vocabulary.Deck

  schema "user_preferences" do
    field :target_language, :string, default: "es"
    field :native_language, :string, default: "en"
    field :ui_locale, :string, default: "en"
    field :use_llm_for_definitions, :boolean, default: false

    belongs_to :user, Langler.Accounts.User
    belongs_to :current_deck, Deck

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [
      :target_language,
      :native_language,
      :ui_locale,
      :user_id,
      :current_deck_id,
      :use_llm_for_definitions
    ])
    |> validate_required([:target_language, :native_language, :user_id])
    |> unique_constraint(:user_id)
  end
end

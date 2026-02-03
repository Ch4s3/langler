defmodule Langler.Accounts.UserLanguage do
  @moduledoc """
  Schema for tracking which languages a user is learning.
  Users can enable multiple languages, but only one is active at a time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_languages" do
    field :language_code, :string
    field :is_active, :boolean, default: false

    belongs_to :user, Langler.Accounts.User
    belongs_to :current_deck, Langler.Vocabulary.Deck

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_language, attrs) do
    user_language
    |> cast(attrs, [:user_id, :language_code, :is_active, :current_deck_id])
    |> validate_required([:user_id, :language_code])
    |> validate_language_code()
    |> unique_constraint([:user_id, :language_code])
    |> unique_constraint(:user_id,
      name: :user_languages_one_active_per_user,
      message: "already has an active language"
    )
  end

  defp validate_language_code(changeset) do
    changeset
    |> validate_change(:language_code, fn :language_code, code ->
      if Langler.Languages.supported?(code) do
        []
      else
        [language_code: "is not a supported language code"]
      end
    end)
  end
end

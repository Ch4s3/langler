defmodule Langler.Accounts.UserPreference do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field :target_language, :string, default: "spanish"
    field :native_language, :string, default: "en"

    belongs_to :user, Langler.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [:target_language, :native_language, :user_id])
    |> validate_required([:target_language, :native_language, :user_id])
    |> unique_constraint(:user_id)
  end
end

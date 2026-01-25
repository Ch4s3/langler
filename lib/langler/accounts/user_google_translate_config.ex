defmodule Langler.Accounts.UserGoogleTranslateConfig do
  @moduledoc """
  Schema for user-specific Google Translate API configurations with encrypted API keys.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_google_translate_configs" do
    belongs_to :user, Langler.Accounts.User
    field :encrypted_api_key, :binary
    field :is_default, :boolean, default: false
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(user_google_translate_config, attrs) do
    user_google_translate_config
    |> cast(attrs, [
      :user_id,
      :encrypted_api_key,
      :is_default,
      :enabled
    ])
    |> validate_required([:user_id, :encrypted_api_key])
  end
end

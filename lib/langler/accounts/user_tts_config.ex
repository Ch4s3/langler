defmodule Langler.Accounts.UserTtsConfig do
  @moduledoc """
  Schema for user-specific TTS provider configurations with encrypted API keys.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_tts_configs" do
    belongs_to :user, Langler.Accounts.User
    field :provider_name, :string
    field :encrypted_api_key, :binary
    field :project_id, :string
    field :location, :string
    field :voice_name, :string
    field :is_default, :boolean, default: false
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(user_tts_config, attrs) do
    user_tts_config
    |> cast(attrs, [
      :user_id,
      :provider_name,
      :encrypted_api_key,
      :project_id,
      :location,
      :voice_name,
      :is_default,
      :enabled
    ])
    |> validate_required([:user_id, :provider_name, :encrypted_api_key])
    |> validate_inclusion(:location, [
      "us-central1",
      "us-east1",
      "us-west1",
      "europe-west1",
      "asia-east1"
    ])

    # project_id is optional - not needed for Generative AI API with API key auth
  end
end

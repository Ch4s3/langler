defmodule Langler.Accounts.UserLlmConfig do
  @moduledoc """
  Schema for user-specific LLM provider configurations with encrypted API keys.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_llm_configs" do
    belongs_to :user, Langler.Accounts.User
    field :provider_name, :string
    field :encrypted_api_key, :binary
    field :model, :string
    field :temperature, :float, default: 0.7
    field :max_tokens, :integer, default: 2000
    field :is_default, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_llm_config, attrs) do
    user_llm_config
    |> cast(attrs, [:user_id, :provider_name, :encrypted_api_key, :model, :temperature, :max_tokens, :is_default])
    |> validate_required([:user_id, :provider_name, :encrypted_api_key])
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)
    |> validate_number(:max_tokens, greater_than: 0)
    |> unique_constraint([:user_id, :provider_name])
  end
end

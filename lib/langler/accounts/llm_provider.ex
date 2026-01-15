defmodule Langler.Accounts.LlmProvider do
  @moduledoc """
  Schema for available LLM provider configurations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "llm_providers" do
    field :name, :string
    field :display_name, :string
    field :adapter_module, :string
    field :requires_api_key, :boolean, default: true
    field :api_key_label, :string
    field :base_url, :string
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(llm_provider, attrs) do
    llm_provider
    |> cast(attrs, [
      :name,
      :display_name,
      :adapter_module,
      :requires_api_key,
      :api_key_label,
      :base_url,
      :enabled
    ])
    |> validate_required([:name, :display_name, :adapter_module])
    |> unique_constraint(:name)
  end
end

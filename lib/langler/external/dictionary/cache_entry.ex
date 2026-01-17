defmodule Langler.External.Dictionary.CacheEntry do
  @moduledoc """
  Ecto schema for dictionary cache entries.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "dictionary_cache_entries" do
    field :table_name, :string
    field :key, :binary
    field :key_hash, :integer
    field :value, :binary
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:table_name, :key, :key_hash, :value, :expires_at])
    |> validate_required([:table_name, :key, :key_hash, :value, :expires_at])
    |> unique_constraint([:table_name, :key_hash],
      name: :dictionary_cache_entries_table_name_key_hash_index
    )
  end
end

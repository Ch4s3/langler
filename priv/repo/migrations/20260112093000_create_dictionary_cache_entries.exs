defmodule Langler.Repo.Migrations.CreateDictionaryCacheEntries do
  use Ecto.Migration

  def change do
    create table(:dictionary_cache_entries) do
      add :table_name, :string, null: false
      add :key, :binary, null: false
      add :key_hash, :bigint, null: false
      add :value, :binary, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dictionary_cache_entries, [:table_name, :key_hash])
    create index(:dictionary_cache_entries, [:expires_at])
  end
end

defmodule Langler.Repo.Migrations.CreateLlmProviders do
  use Ecto.Migration

  def change do
    create table(:llm_providers) do
      add :name, :string, null: false
      add :display_name, :string, null: false
      add :adapter_module, :string, null: false
      add :requires_api_key, :boolean, default: true, null: false
      add :api_key_label, :string
      add :base_url, :string
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:llm_providers, [:name])
  end
end

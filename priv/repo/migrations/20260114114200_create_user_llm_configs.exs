defmodule Langler.Repo.Migrations.CreateUserLlmConfigs do
  use Ecto.Migration

  def change do
    create table(:user_llm_configs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider_name, :string, null: false
      add :encrypted_api_key, :binary, null: false
      add :model, :string
      add :temperature, :float, default: 0.7
      add :max_tokens, :integer, default: 2000
      add :is_default, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_llm_configs, [:user_id, :provider_name])
    create index(:user_llm_configs, [:user_id, :is_default])
  end
end

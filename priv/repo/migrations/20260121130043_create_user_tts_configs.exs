defmodule Langler.Repo.Migrations.CreateUserTtsConfigs do
  use Ecto.Migration

  def change do
    create table(:user_tts_configs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider_name, :string, null: false, default: "vertex_ai"
      add :encrypted_api_key, :binary, null: false
      add :project_id, :string, null: false
      add :location, :string, null: false, default: "us-central1"
      add :voice_name, :string
      add :is_default, :boolean, default: false, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_tts_configs, [:user_id, :is_default])
  end
end

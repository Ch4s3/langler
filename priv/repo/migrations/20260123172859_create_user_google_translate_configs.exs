defmodule Langler.Repo.Migrations.CreateUserGoogleTranslateConfigs do
  use Ecto.Migration

  def change do
    create table(:user_google_translate_configs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :encrypted_api_key, :binary, null: false
      add :is_default, :boolean, default: false, null: false
      add :enabled, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_google_translate_configs, [:user_id, :is_default])
  end
end

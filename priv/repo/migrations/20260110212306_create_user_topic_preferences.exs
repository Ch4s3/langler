defmodule Langler.Repo.Migrations.CreateUserTopicPreferences do
  use Ecto.Migration

  def change do
    create table(:user_topic_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :topic, :string, null: false
      add :weight, :decimal, default: 1.0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_topic_preferences, [:user_id, :topic])
    create index(:user_topic_preferences, [:user_id])
  end
end

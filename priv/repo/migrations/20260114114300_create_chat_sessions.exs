defmodule Langler.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string
      add :context_type, :string
      add :context_id, :integer
      add :llm_provider, :string, null: false
      add :llm_model, :string
      add :target_language, :string, null: false
      add :native_language, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_sessions, [:user_id, :inserted_at])
    create index(:chat_sessions, [:user_id, :context_type, :context_id])
  end
end

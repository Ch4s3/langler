defmodule Langler.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :chat_session_id, references(:chat_sessions, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :encrypted_content, :binary, null: false
      add :content_hash, :string, null: false
      add :token_count, :integer
      add :metadata, :jsonb

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:chat_session_id, :inserted_at])
    create index(:chat_messages, [:content_hash])
  end
end

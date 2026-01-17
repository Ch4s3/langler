defmodule Langler.Repo.Migrations.AddPinnedToChatSessions do
  use Ecto.Migration

  def change do
    alter table(:chat_sessions) do
      add :pinned, :boolean, default: false, null: false
    end

    create index(:chat_sessions, [:user_id, :pinned, :inserted_at])
  end
end

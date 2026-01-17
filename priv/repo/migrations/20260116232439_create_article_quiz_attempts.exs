defmodule Langler.Repo.Migrations.CreateArticleQuizAttempts do
  use Ecto.Migration

  def change do
    create table(:article_quiz_attempts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :chat_session_id, references(:chat_sessions, on_delete: :nilify_all), null: true
      add :attempt_number, :integer, null: false
      add :score, :integer, null: true
      add :max_score, :integer, null: true
      add :result_json, :jsonb, null: true
      add :started_at, :utc_datetime, null: true
      add :completed_at, :utc_datetime, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:article_quiz_attempts, [:user_id, :article_id])
    create index(:article_quiz_attempts, [:user_id, :article_id, :score])
    create index(:article_quiz_attempts, [:chat_session_id])
  end
end

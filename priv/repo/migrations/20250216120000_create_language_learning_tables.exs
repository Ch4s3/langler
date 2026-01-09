defmodule Langler.Repo.Migrations.CreateLanguageLearningTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:articles) do
      add :title, :string, null: false
      add :url, :string, null: false
      add :source, :string
      add :language, :string, null: false
      add :content, :text
      add :extracted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:articles, [:url])

    create table(:article_users) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "imported"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:article_users, [:article_id, :user_id])

    create table(:sentences) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :content, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sentences, [:article_id])

    create table(:words) do
      add :normalized_form, :string, null: false
      add :lemma, :string
      add :language, :string, null: false
      add :part_of_speech, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:words, [:normalized_form, :language])

    create table(:word_occurrences) do
      add :word_id, references(:words, on_delete: :delete_all), null: false
      add :sentence_id, references(:sentences, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :context, :text

      timestamps(type: :utc_datetime)
    end

    create index(:word_occurrences, [:sentence_id])
    create index(:word_occurrences, [:word_id])

    create table(:fsrs_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :word_id, references(:words, on_delete: :delete_all), null: false
      add :ease_factor, :float, null: false, default: 2.5
      add :interval, :integer, null: false, default: 0
      add :due_date, :utc_datetime
      add :repetitions, :integer, null: false, default: 0
      add :quality_history, {:array, :integer}, null: false, default: []
      add :last_reviewed_at, :utc_datetime
      add :stability, :float
      add :difficulty, :float
      add :retrievability, :float
      add :state, :string, null: false, default: "learning"
      add :step, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:fsrs_items, [:user_id, :due_date])
    create unique_index(:fsrs_items, [:user_id, :word_id])

    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :target_language, :string, null: false, default: "spanish"
      add :native_language, :string, null: false, default: "en"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_preferences, [:user_id])
  end
end

defmodule Langler.Repo.Migrations.AddDifficultyToArticles do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      add :difficulty_score, :float
      add :unique_word_count, :integer
      add :avg_word_frequency, :float
      add :avg_sentence_length, :float
    end

    alter table(:discovered_articles) do
      add :difficulty_score, :float
      add :avg_sentence_length, :float
    end

    create index(:articles, [:difficulty_score])
  end
end

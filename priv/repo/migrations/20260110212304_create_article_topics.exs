defmodule Langler.Repo.Migrations.CreateArticleTopics do
  use Ecto.Migration

  def change do
    create table(:article_topics) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :topic, :string, null: false
      add :confidence, :decimal, null: false
      add :language, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:article_topics, [:article_id])
    create index(:article_topics, [:topic])
    create unique_index(:article_topics, [:article_id, :topic])
  end
end

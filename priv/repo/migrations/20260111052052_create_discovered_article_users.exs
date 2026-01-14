defmodule Langler.Repo.Migrations.CreateDiscoveredArticleUsers do
  use Ecto.Migration

  def change do
    create table(:discovered_article_users) do
      add :discovered_article_id, references(:discovered_articles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "recommended"
      add :imported_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:discovered_article_users, [:discovered_article_id, :user_id])
    create index(:discovered_article_users, [:user_id, :status])
  end
end

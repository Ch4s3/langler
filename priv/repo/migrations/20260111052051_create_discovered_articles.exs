defmodule Langler.Repo.Migrations.CreateDiscoveredArticles do
  use Ecto.Migration

  def change do
    create table(:discovered_articles) do
      add :source_site_id, references(:source_sites, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :canonical_url, :string
      add :title, :string
      add :summary, :string
      add :published_at, :utc_datetime
      add :discovered_at, :utc_datetime, null: false
      add :article_id, references(:articles, on_delete: :nilify_all)
      add :status, :string, default: "new"
      add :language, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:discovered_articles, [:source_site_id, :url])
    create index(:discovered_articles, [:article_id])
    create index(:discovered_articles, [:discovered_at])
    create index(:discovered_articles, [:status, :published_at])
  end
end

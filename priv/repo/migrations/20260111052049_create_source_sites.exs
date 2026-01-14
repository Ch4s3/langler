defmodule Langler.Repo.Migrations.CreateSourceSites do
  use Ecto.Migration

  def change do
    create table(:source_sites) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :rss_url, :string
      add :scraping_config, :map, default: %{}
      add :discovery_method, :string, null: false
      add :check_interval_hours, :integer, default: 24
      add :last_checked_at, :utc_datetime
      add :etag, :string
      add :last_modified, :string
      add :last_error, :string
      add :last_error_at, :utc_datetime
      add :is_active, :boolean, default: true
      add :language, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:source_sites, [:url])
    create index(:source_sites, [:is_active, :last_checked_at])
  end
end

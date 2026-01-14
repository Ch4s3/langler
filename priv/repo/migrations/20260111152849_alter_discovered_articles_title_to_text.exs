defmodule Langler.Repo.Migrations.AlterDiscoveredArticlesTitleToText do
  use Ecto.Migration

  def change do
    alter table(:discovered_articles) do
      modify :title, :text
      modify :summary, :text
    end
  end
end

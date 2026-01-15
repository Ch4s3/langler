defmodule Langler.Content.DiscoveredArticle do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "discovered_articles" do
    field :url, :string
    field :canonical_url, :string
    field :title, :string
    field :summary, :string
    field :published_at, :utc_datetime
    field :discovered_at, :utc_datetime
    field :status, :string, default: "new"
    field :language, :string
    field :difficulty_score, :float
    field :avg_sentence_length, :float

    belongs_to :source_site, Langler.Content.SourceSite
    belongs_to :article, Langler.Content.Article
    has_many :discovered_article_users, Langler.Content.DiscoveredArticleUser

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(discovered_article, attrs) do
    discovered_article
    |> cast(attrs, [
      :source_site_id,
      :url,
      :canonical_url,
      :title,
      :summary,
      :published_at,
      :discovered_at,
      :article_id,
      :status,
      :language,
      :difficulty_score,
      :avg_sentence_length
    ])
    |> validate_required([:source_site_id, :url, :discovered_at])
    |> validate_inclusion(:status, ["new", "imported", "skipped"])
    |> unique_constraint([:source_site_id, :url])
  end
end

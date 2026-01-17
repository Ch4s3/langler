defmodule Langler.Content.SourceSite do
  @moduledoc """
  Ecto schema for source sites.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "source_sites" do
    field :name, :string
    field :url, :string
    field :rss_url, :string
    field :scraping_config, :map, default: %{}
    field :discovery_method, :string
    field :check_interval_hours, :integer, default: 24
    field :last_checked_at, :utc_datetime
    field :etag, :string
    field :last_modified, :string
    field :last_error, :string
    field :last_error_at, :utc_datetime
    field :is_active, :boolean, default: true
    field :language, :string

    has_many :discovered_articles, Langler.Content.DiscoveredArticle

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(source_site, attrs) do
    source_site
    |> cast(attrs, [
      :name,
      :url,
      :rss_url,
      :scraping_config,
      :discovery_method,
      :check_interval_hours,
      :last_checked_at,
      :etag,
      :last_modified,
      :last_error,
      :last_error_at,
      :is_active,
      :language
    ])
    |> validate_required([:name, :url, :discovery_method, :language])
    |> validate_inclusion(:discovery_method, ["rss", "scraping", "hybrid"])
    |> validate_number(:check_interval_hours, greater_than: 0)
    |> unique_constraint(:url)
  end
end

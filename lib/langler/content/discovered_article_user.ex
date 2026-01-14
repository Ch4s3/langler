defmodule Langler.Content.DiscoveredArticleUser do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "discovered_article_users" do
    field :status, :string, default: "recommended"
    field :imported_at, :utc_datetime

    belongs_to :discovered_article, Langler.Content.DiscoveredArticle
    belongs_to :user, Langler.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(discovered_article_user, attrs) do
    discovered_article_user
    |> cast(attrs, [:discovered_article_id, :user_id, :status, :imported_at])
    |> validate_required([:discovered_article_id, :user_id])
    |> validate_inclusion(:status, ["recommended", "imported", "dismissed"])
    |> unique_constraint([:discovered_article_id, :user_id])
  end
end

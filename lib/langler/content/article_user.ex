defmodule Langler.Content.ArticleUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "article_users" do
    field :status, :string, default: "imported"

    belongs_to :article, Langler.Content.Article
    belongs_to :user, Langler.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(article_user, attrs) do
    article_user
    |> cast(attrs, [:status, :article_id, :user_id])
    |> validate_required([:status, :article_id, :user_id])
    |> unique_constraint([:article_id, :user_id])
  end
end

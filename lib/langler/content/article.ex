defmodule Langler.Content.Article do
  use Ecto.Schema
  import Ecto.Changeset

  schema "articles" do
    field :title, :string
    field :url, :string
    field :source, :string
    field :language, :string
    field :content, :string
    field :extracted_at, :utc_datetime

    has_many :sentences, Langler.Content.Sentence
    has_many :article_users, Langler.Content.ArticleUser
    has_many :users, through: [:article_users, :user]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :url, :source, :language, :content, :extracted_at])
    |> validate_required([:title, :url, :language])
    |> unique_constraint(:url)
  end
end

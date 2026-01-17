defmodule Langler.Content.Article do
  @moduledoc """
  Ecto schema for articles.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "articles" do
    field :title, :string
    field :url, :string
    field :source, :string
    field :language, :string
    field :content, :string
    field :extracted_at, :utc_datetime
    field :difficulty_score, :float
    field :unique_word_count, :integer
    field :avg_word_frequency, :float
    field :avg_sentence_length, :float

    has_many :sentences, Langler.Content.Sentence
    has_many :article_users, Langler.Content.ArticleUser
    has_many :users, through: [:article_users, :user]
    has_many :article_topics, Langler.Content.ArticleTopic

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :url, :source, :language, :content, :extracted_at])
    |> validate_required([:title, :url, :language])
    |> unique_constraint(:url)
  end
end

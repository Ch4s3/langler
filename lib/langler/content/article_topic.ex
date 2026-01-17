defmodule Langler.Content.ArticleTopic do
  @moduledoc """
  Ecto schema for article topics.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "article_topics" do
    field :topic, :string
    field :confidence, :decimal
    field :language, :string
    belongs_to :article, Langler.Content.Article

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(article_topic, attrs) do
    article_topic
    |> cast(attrs, [:article_id, :topic, :confidence, :language])
    |> validate_required([:article_id, :topic, :confidence, :language])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint([:article_id, :topic])
  end
end

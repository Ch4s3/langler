defmodule Langler.Content.Sentence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "sentences" do
    field :position, :integer
    field :content, :string

    belongs_to :article, Langler.Content.Article
    has_many :word_occurrences, Langler.Vocabulary.WordOccurrence

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sentence, attrs) do
    sentence
    |> cast(attrs, [:position, :content, :article_id])
    |> validate_required([:position, :content, :article_id])
    |> assoc_constraint(:article)
  end
end

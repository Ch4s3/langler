defmodule Langler.ContentFixtures do
  @moduledoc false

  alias Langler.AccountsFixtures
  alias Langler.Content

  def article_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || AccountsFixtures.user_fixture()
    attrs = Map.drop(attrs, [:user])

    {:ok, article} =
      attrs
      |> Enum.into(%{
        title: "Sample Article",
        url: "https://example.com/articles/#{System.unique_integer([:positive])}",
        language: "spanish",
        source: "example",
        content: "Hola mundo."
      })
      |> Content.create_article()

    {:ok, _} = Content.ensure_article_user(article, user.id)

    article
  end

  def sentence_fixture(article \\ article_fixture(), attrs \\ %{}) do
    {:ok, sentence} =
      attrs
      |> Enum.into(%{
        position: 0,
        content: "Hola mundo.",
        article_id: article.id
      })
      |> Content.create_sentence()

    sentence
  end
end

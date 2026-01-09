defmodule Langler.ContentTest do
  use Langler.DataCase, async: true

  alias Langler.Content
  alias Langler.AccountsFixtures

  test "create_article/1 inserts an article and associates user" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Hola",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    assert article.title == "Hola"

    {:ok, article_user} = Content.ensure_article_user(article, user.id)
    assert article_user.user_id == user.id
  end

  test "list_articles_for_user/1 returns scoped articles" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Scoped",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    {:ok, _} = Content.ensure_article_user(article, user.id)
    article_id = article.id

    assert [%Content.Article{id: ^article_id}] = Content.list_articles_for_user(user.id)
  end

  test "create_sentence/1 stores sentence for article" do
    user = AccountsFixtures.user_fixture()

    {:ok, article} =
      Content.create_article(%{
        title: "Sentences",
        url: "https://example.com/#{System.unique_integer()}",
        language: "spanish"
      })

    {:ok, _} = Content.ensure_article_user(article, user.id)

    {:ok, sentence} =
      Content.create_sentence(%{
        position: 0,
        content: "Hola mundo.",
        article_id: article.id
      })

    assert sentence.article_id == article.id
    assert [^sentence] = Content.list_sentences(article)
  end
end

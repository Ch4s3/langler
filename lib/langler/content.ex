defmodule Langler.Content do
  @moduledoc """
  Content ingestion domain (articles, user associations, sentences).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Content.{Article, ArticleUser, Sentence}

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.inserted_at])
  end

  def list_articles_for_user(user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([_a, au], au.user_id == ^user_id)
    |> order_by([a, _], desc: a.inserted_at)
    |> Repo.all()
  end

  def get_article!(id), do: Repo.get!(Article, id)

  def get_article_by_url(url), do: Repo.get_by(Article, url: url)

  def create_article(attrs \\ %{}) do
    %Article{}
    |> Article.changeset(attrs)
    |> Repo.insert()
  end

  def update_article(%Article{} = article, attrs) do
    article
    |> Article.changeset(attrs)
    |> Repo.update()
  end

  def change_article(%Article{} = article, attrs \\ %{}) do
    Article.changeset(article, attrs)
  end

  def ensure_article_user(%Article{} = article, user_id, attrs \\ %{}) do
    defaults = Map.merge(%{article_id: article.id, user_id: user_id}, attrs)

    case Repo.get_by(ArticleUser, article_id: article.id, user_id: user_id) do
      nil ->
        %ArticleUser{}
        |> ArticleUser.changeset(defaults)
        |> Repo.insert()

      article_user ->
        attrs =
          attrs
          |> Enum.into(%{})
          |> Map.put(:article_id, article_user.article_id)
          |> Map.put(:user_id, article_user.user_id)

        update_article_user(article_user, attrs)
    end
  end

  def update_article_user(%ArticleUser{} = article_user, attrs) do
    article_user
    |> ArticleUser.changeset(attrs)
    |> Repo.update()
  end

  def list_sentences(%Article{} = article) do
    Sentence
    |> where(article_id: ^article.id)
    |> order_by([s], asc: s.position)
    |> Repo.all()
  end

  def create_sentence(attrs \\ %{}) do
    %Sentence{}
    |> Sentence.changeset(attrs)
    |> Repo.insert()
  end
end

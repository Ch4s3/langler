defmodule Langler.Content do
  @moduledoc """
  Content ingestion domain (articles, user associations, sentences).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Content.{
    Article,
    ArticleUser,
    ArticleTopic,
    Sentence,
    SourceSite,
    DiscoveredArticle,
    DiscoveredArticleUser
  }

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.inserted_at])
  end

  def list_articles_for_user(user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([_a, au], au.user_id == ^user_id and au.status != "archived")
    |> order_by([a, _], desc: a.inserted_at)
    |> preload(:article_topics)
    |> Repo.all()
  end

  def list_archived_articles_for_user(user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([_a, au], au.user_id == ^user_id and au.status == "archived")
    |> order_by([a, _], desc: a.inserted_at)
    |> Repo.all()
  end

  def get_article!(id), do: Repo.get!(Article, id)

  def get_article_by_url(url), do: Repo.get_by(Article, url: url)

  def get_article_for_user!(user_id, article_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([a, au], a.id == ^article_id and au.user_id == ^user_id)
    |> Repo.one!()
  end

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

  def delete_article_for_user(user_id, article_id) do
    Repo.transaction(fn ->
      article_user = Repo.get_by(ArticleUser, article_id: article_id, user_id: user_id)

      if is_nil(article_user) do
        Repo.rollback(:not_found)
      else
        Repo.delete!(article_user)
      end

      remaining =
        ArticleUser
        |> where(article_id: ^article_id)
        |> select([au], count(au.id))
        |> Repo.one()

      if remaining == 0 do
        article = Repo.get!(Article, article_id)
        Repo.delete!(article)
      end

      :ok
    end)
  end

  def archive_article_for_user(user_id, article_id) do
    user_article = Repo.get_by(ArticleUser, article_id: article_id, user_id: user_id)

    case user_article do
      nil -> {:error, :not_found}
      article_user -> update_article_user(article_user, %{status: "archived"})
    end
  end

  def restore_article_for_user(user_id, article_id) do
    user_article = Repo.get_by(ArticleUser, article_id: article_id, user_id: user_id)

    case user_article do
      nil -> {:error, :not_found}
      article_user -> update_article_user(article_user, %{status: "imported"})
    end
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
    |> Repo.preload(word_occurrences: [:word])
  end

  def create_sentence(attrs \\ %{}) do
    %Sentence{}
    |> Sentence.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Tags an article with topics and confidence scores.
  Replaces any existing topics for the article.
  """
  @spec tag_article(Article.t(), list({String.t(), float()})) :: :ok | {:error, term()}
  def tag_article(%Article{} = article, topics) when is_list(topics) do
    Repo.transaction(fn ->
      # Delete existing topics
      Repo.delete_all(from(at in ArticleTopic, where: at.article_id == ^article.id))

      # Insert new topics
      Enum.each(topics, fn {topic_id, confidence} ->
        %ArticleTopic{}
        |> ArticleTopic.changeset(%{
          article_id: article.id,
          topic: topic_id,
          confidence: Decimal.from_float(confidence),
          language: article.language
        })
        |> Repo.insert!()
      end)

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets articles filtered by topic for a specific user.
  """
  @spec get_articles_by_topic(String.t(), integer()) :: [Article.t()]
  def get_articles_by_topic(topic, user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> join(:inner, [a, au], at in ArticleTopic, on: at.article_id == a.id)
    |> where([a, au, at], au.user_id == ^user_id and at.topic == ^topic and au.status != "archived")
    |> order_by([a, au, at], desc: a.inserted_at)
    |> preload(:article_topics)
    |> Repo.all()
  end

  @doc """
  Lists all topics for an article.
  """
  @spec list_topics_for_article(integer()) :: [ArticleTopic.t()]
  def list_topics_for_article(article_id) do
    ArticleTopic
    |> where(article_id: ^article_id)
    |> order_by([at], desc: at.confidence)
    |> Repo.all()
  end

  @doc """
  Gets all unique topics for a user's articles.
  """
  @spec get_user_topics(integer()) :: [String.t()]
  def get_user_topics(user_id) do
    ArticleTopic
    |> join(:inner, [at], a in Article, on: at.article_id == a.id)
    |> join(:inner, [at, a], au in ArticleUser, on: au.article_id == a.id)
    |> where([at, a, au], au.user_id == ^user_id and au.status != "archived")
    |> distinct([at], at.topic)
    |> select([at], at.topic)
    |> Repo.all()
  end

  @doc """
  Scores an article for a user based on their topic preferences.
  Returns a score from 0.0 to 2.0+ (higher is better match).
  """
  @spec score_article_for_user(Article.t(), integer()) :: float()
  def score_article_for_user(%Article{} = article, user_id) do
    user_topics = Langler.Accounts.get_user_topic_preferences(user_id)
    article_topics = list_topics_for_article(article.id)

    base_score =
      Enum.reduce(article_topics, 0.0, fn at, acc ->
        user_pref = Map.get(user_topics, at.topic, Decimal.new("1.0"))
        weight = Decimal.to_float(user_pref)
        confidence = Decimal.to_float(at.confidence)
        acc + (confidence * weight)
      end)

    # Add freshness bonus (newer articles get slight boost)
    days_old = DateTime.diff(DateTime.utc_now(), article.inserted_at, :day)
    freshness_bonus = max(0.0, 1.0 - (days_old / 30.0)) * 0.1

    base_score + freshness_bonus
  end

  @doc """
  Gets recommended articles for a user (articles not yet imported by them).
  Returns a list of maps with article data (from Article or DiscoveredArticle).
  Sorted by recommendation score descending.
  """
  @spec get_recommended_articles(integer(), integer()) :: [map()]
  def get_recommended_articles(user_id, limit \\ 10) do
    # Get discovered articles first (if any)
    discovered = list_recommendations_for_user(user_id, limit: limit * 2)

    # Also get regular articles not imported by user
    user_article_ids =
      ArticleUser
      |> where([au], au.user_id == ^user_id)
      |> select([au], au.article_id)
      |> Repo.all()

    regular_articles =
      Article
      |> where([a], a.id not in ^user_article_ids)
      |> preload(:article_topics)
      |> Repo.all()

    # Convert discovered articles to article-like maps
    discovered_article_maps =
      Enum.map(discovered, fn da ->
        if da.article do
          # Already imported - use the article
          article_to_map(da.article)
        else
          # Not yet imported - create map from discovered article
          %{
            id: nil,
            title: da.title || da.url,
            url: da.url,
            source: da.source_site && da.source_site.name,
            language: da.language || "spanish",
            content: da.summary || "",
            inserted_at: da.published_at || da.discovered_at || DateTime.utc_now(),
            published_at: da.published_at || da.discovered_at,
            article_topics: [],
            discovered_article_id: da.id,
            is_discovered: true
          }
        end
      end)

    # Convert regular articles to maps
    regular_article_maps = Enum.map(regular_articles, &article_to_map/1)

    all_articles = discovered_article_maps ++ regular_article_maps

    all_articles
    |> Enum.map(fn article_map ->
      # Score using the article if available, otherwise use a default score
      score =
        if article_map.id do
          article = Repo.get(Article, article_map.id) |> Repo.preload(:article_topics)
          score_article_for_user(article, user_id)
        else
          # For discovered articles without content, give a base score
          0.5
        end

      {article_map, score}
    end)
    |> Enum.filter(fn {_article, score} -> score > 0.0 end)
    |> Enum.sort_by(fn {_article, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {article, _score} -> article end)
  end

  defp article_to_map(%Article{} = article) do
    %{
      id: article.id,
      title: article.title,
      url: article.url,
      source: article.source,
      language: article.language,
      content: article.content || "",
      inserted_at: article.inserted_at,
      published_at: article.inserted_at,
      article_topics: article.article_topics || [],
      discovered_article_id: nil,
      is_discovered: false
    }
  end

  ## Source Sites

  def list_source_sites do
    Repo.all(from s in SourceSite, order_by: [desc: s.inserted_at])
  end

  def list_active_source_sites do
    Repo.all(
      from s in SourceSite,
        where: s.is_active == true,
        order_by: [asc: s.last_checked_at]
    )
  end

  def get_source_site!(id), do: Repo.get!(SourceSite, id)

  def get_source_site(id), do: Repo.get(SourceSite, id)

  def create_source_site(attrs \\ %{}) do
    %SourceSite{}
    |> SourceSite.changeset(attrs)
    |> Repo.insert()
  end

  def update_source_site(%SourceSite{} = source_site, attrs) do
    source_site
    |> SourceSite.changeset(attrs)
    |> Repo.update()
  end

  def delete_source_site(%SourceSite{} = source_site) do
    Repo.delete(source_site)
  end

  def mark_source_checked(%SourceSite{} = source_site, etag \\ nil, last_modified \\ nil) do
    attrs = %{
      last_checked_at: DateTime.utc_now(),
      last_error: nil,
      last_error_at: nil
    }

    attrs =
      if etag, do: Map.put(attrs, :etag, etag), else: attrs

    attrs =
      if last_modified, do: Map.put(attrs, :last_modified, last_modified), else: attrs

    update_source_site(source_site, attrs)
  end

  def mark_source_error(%SourceSite{} = source_site, error_message) do
    update_source_site(source_site, %{
      last_error: error_message,
      last_error_at: DateTime.utc_now()
    })
  end

  ## Discovered Articles

  def upsert_discovered_articles(source_site_id, articles) when is_list(articles) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    entries =
      Enum.map(articles, fn attrs ->
        discovered_at =
          if attrs[:discovered_at] || attrs["discovered_at"] do
            discovered = attrs[:discovered_at] || attrs["discovered_at"]
            if is_struct(discovered, DateTime), do: DateTime.truncate(discovered, :second), else: now
          else
            now
          end

        published_at =
          if attrs[:published_at] || attrs["published_at"] do
            pub = attrs[:published_at] || attrs["published_at"]
            if is_struct(pub, DateTime), do: DateTime.truncate(pub, :second), else: nil
          else
            nil
          end

        %{
          source_site_id: source_site_id,
          url: attrs[:url] || attrs["url"],
          canonical_url: attrs[:canonical_url] || attrs["canonical_url"],
          title: attrs[:title] || attrs["title"],
          summary: attrs[:summary] || attrs["summary"],
          published_at: published_at,
          discovered_at: discovered_at,
          status: attrs[:status] || attrs["status"] || "new",
          language: attrs[:language] || attrs["language"],
          inserted_at: now,
          updated_at: now
        }
      end)

    # Use on_conflict to update title and summary if they're missing or changed
    Repo.insert_all(DiscoveredArticle, entries,
      on_conflict: {:replace_all_except, [:id, :inserted_at, :article_id, :status]},
      conflict_target: [:source_site_id, :url]
    )
  end

  def get_discovered_article!(id), do: Repo.get!(DiscoveredArticle, id)

  def get_discovered_article(id), do: Repo.get(DiscoveredArticle, id)

  def get_discovered_article_by_url(url) do
    Repo.one(from da in DiscoveredArticle, where: da.url == ^url, limit: 1)
  end

  def update_discovered_article(%DiscoveredArticle{} = discovered_article, attrs) do
    discovered_article
    |> DiscoveredArticle.changeset(attrs)
    |> Repo.update()
  end

  def list_recommendations_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status, "recommended")

    # Get discovered articles that haven't been imported by this user
    # and are either new or recommended to this user
    user_imported_article_ids =
      ArticleUser
      |> where([au], au.user_id == ^user_id)
      |> select([au], au.article_id)
      |> Repo.all()

    from(da in DiscoveredArticle,
      left_join: dau in DiscoveredArticleUser,
      on: dau.discovered_article_id == da.id and dau.user_id == ^user_id,
      where: da.status == "new" or (dau.status == ^status and is_nil(da.article_id)),
      where: da.article_id not in ^user_imported_article_ids or is_nil(da.article_id),
      preload: [:source_site, :article, :article_topics],
      order_by: [desc: da.discovered_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## Discovered Article Users

  def get_or_create_discovered_article_user(discovered_article_id, user_id, attrs \\ %{}) do
    case Repo.get_by(DiscoveredArticleUser,
           discovered_article_id: discovered_article_id,
           user_id: user_id
         ) do
      nil ->
        %DiscoveredArticleUser{}
        |> DiscoveredArticleUser.changeset(
          Map.merge(attrs, %{
            discovered_article_id: discovered_article_id,
            user_id: user_id
          })
        )
        |> Repo.insert()

      dau ->
        {:ok, dau}
    end
  end

  def update_discovered_article_user(%DiscoveredArticleUser{} = dau, attrs) do
    dau
    |> DiscoveredArticleUser.changeset(attrs)
    |> Repo.update()
  end

  def mark_discovered_article_imported(discovered_article_id, user_id) do
    with {:ok, dau} <-
           get_or_create_discovered_article_user(discovered_article_id, user_id) do
      update_discovered_article_user(dau, %{
        status: "imported",
        imported_at: DateTime.utc_now()
      })
    end
  end

  def mark_discovered_article_dismissed(discovered_article_id, user_id) do
    with {:ok, dau} <-
           get_or_create_discovered_article_user(discovered_article_id, user_id) do
      update_discovered_article_user(dau, %{status: "dismissed"})
    end
  end
end

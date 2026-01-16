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
    |> where(
      [a, au, at],
      au.user_id == ^user_id and at.topic == ^topic and au.status != "archived"
    )
    |> order_by([a, au, at], desc: a.inserted_at)
    |> preload(:article_topics)
    |> Repo.all()
  end

  @doc """
  Lists all topics for an article.
  """
  @spec list_topics_for_article(integer() | nil) :: [ArticleTopic.t()]
  def list_topics_for_article(nil), do: []

  def list_topics_for_article(article_id) when is_integer(article_id) do
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
        acc + confidence * weight
      end)

    # Add freshness bonus (newer articles get slight boost)
    days_old = DateTime.diff(DateTime.utc_now(), article.inserted_at, :day)
    freshness_bonus = max(0.0, 1.0 - days_old / 30.0) * 0.1

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
      |> Enum.filter(&(not is_nil(&1)))

    regular_articles =
      if Enum.empty?(user_article_ids) do
        Article
        |> preload(:article_topics)
        |> Repo.all()
      else
        Article
        |> where([a], a.id not in ^user_article_ids)
        |> preload(:article_topics)
        |> Repo.all()
      end

    # Convert discovered articles to article-like maps
    # Fetch titles for articles that don't have them
    discovered_article_maps =
      discovered
      |> Enum.map(fn da ->
        if da.article do
          # Already imported - use the article
          {da, article_to_map(da.article)}
        else
          # Not yet imported - will fetch title if needed
          {da, nil}
        end
      end)
      |> fetch_titles_for_discovered_articles()

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
      is_discovered: false,
      difficulty_score: article.difficulty_score,
      avg_sentence_length: article.avg_sentence_length
    }
  end

  # Fetch titles for discovered articles that don't have them
  defp fetch_titles_for_discovered_articles(discovered_with_maps) do
    # Separate articles that need title fetching from those already mapped
    # If article_map is nil, it always needs fetching (even if da.title exists)
    {needs_fetch, already_mapped} =
      Enum.split_with(discovered_with_maps, fn
        {_da, article_map} when is_map(article_map) -> false
        # nil article_map always needs fetching
        {_da, nil} -> true
        {da, _} -> is_nil(da.title) or da.title == ""
      end)

    # Fetch titles concurrently for articles that need them
    fetched_titles =
      if Enum.empty?(needs_fetch) do
        %{}
      else
        needs_fetch
        |> Enum.map(fn {da, _} -> da.url end)
        |> Task.async_stream(
          fn url ->
            case fetch_title_from_url(url) do
              {:ok, title} when is_binary(title) and title != "" -> {url, title}
              _ -> {url, nil}
            end
          end,
          max_concurrency: 5,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{}, fn
          {:ok, {url, title}}, acc when not is_nil(title) -> Map.put(acc, url, title)
          _, acc -> acc
        end)
      end

    # Update discovered articles with fetched titles
    updated_needs_fetch =
      needs_fetch
      |> Enum.map(fn {da, _} ->
        title = Map.get(fetched_titles, da.url) || da.title

        %{
          id: nil,
          title: title || da.url,
          url: da.url,
          source: da.source_site && da.source_site.name,
          language: da.language || "spanish",
          content: da.summary || "",
          inserted_at: da.published_at || da.discovered_at || DateTime.utc_now(),
          published_at: da.published_at || da.discovered_at,
          article_topics: [],
          discovered_article_id: da.id,
          is_discovered: true,
          difficulty_score: da.difficulty_score,
          avg_sentence_length: da.avg_sentence_length
        }
      end)

    # Combine with already mapped articles
    # Filter out any nil article_maps that might have slipped through
    already_mapped_maps =
      already_mapped
      |> Enum.map(fn {_da, article_map} -> article_map end)
      |> Enum.filter(&(not is_nil(&1)))

    already_mapped_maps ++ updated_needs_fetch
  end

  # Fetch and extract title from a URL
  defp fetch_title_from_url(url) do
    req =
      Req.new(
        url: url,
        method: :get,
        redirect: :follow,
        headers: [{"user-agent", "LanglerBot/0.1"}],
        receive_timeout: 5_000
      )

    case Req.get(req) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        extract_title_from_html(body)

      _ ->
        {:error, :fetch_failed}
    end
  end

  # Extract title from HTML
  defp extract_title_from_html(html) do
    with {:ok, document} <- Floki.parse_document(html) do
      # Try <title> tag first
      title =
        document
        |> Floki.find("title")
        |> Floki.text()
        |> String.trim()

      if title != "" do
        {:ok, title}
      else
        # Try <h1> as fallback
        h1_title =
          document
          |> Floki.find("h1")
          |> Enum.at(0)
          |> case do
            nil -> nil
            h1 -> Floki.text(h1) |> String.trim()
          end

        if h1_title && h1_title != "" do
          {:ok, h1_title}
        else
          {:error, :no_title}
        end
      end
    else
      _ -> {:error, :parse_failed}
    end
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

            if is_struct(discovered, DateTime),
              do: DateTime.truncate(discovered, :second),
              else: now
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
      |> where([au], not is_nil(au.article_id))
      |> select([au], au.article_id)
      |> Repo.all()

    # Build query - handle nil article_id separately to avoid unsafe nil comparisons
    base_query =
      from(da in DiscoveredArticle,
        left_join: dau in DiscoveredArticleUser,
        on: dau.discovered_article_id == da.id and dau.user_id == ^user_id,
        where: da.status == "new" or (dau.status == ^status and is_nil(da.article_id))
      )

    # Filter by article_id - handle nil separately
    query =
      if Enum.empty?(user_imported_article_ids) do
        # No imported articles, so all discovered articles with nil article_id are eligible
        base_query
        |> where([da], is_nil(da.article_id))
      else
        # Articles that either have nil article_id OR (non-nil article_id not in user's imported list)
        base_query
        |> where([da], is_nil(da.article_id))
        |> or_where(
          [da],
          not is_nil(da.article_id) and da.article_id not in ^user_imported_article_ids
        )
      end

    # Get articles from all sources, mixing them by discovery time
    # This ensures we don't only show articles from the most recently discovered source
    query
    |> preload([:source_site, :article])
    |> order_by([da], desc: da.discovered_at, desc: da.id)
    |> limit(^limit)
    |> Repo.all()
    |> mix_by_source()
  end

  # Mix articles from different sources to ensure diversity
  defp mix_by_source(articles) do
    # Group by source site
    by_source =
      articles
      |> Enum.group_by(fn da ->
        if Ecto.assoc_loaded?(da.source_site) && da.source_site do
          da.source_site.id
        else
          :unknown
        end
      end)

    # If we only have one source, return as-is
    if map_size(by_source) <= 1 do
      articles
    else
      # Round-robin: take one from each source in turn
      sources = Map.keys(by_source)
      max_per_source = div(length(articles), length(sources)) + 1

      sources
      |> Enum.flat_map(fn source_id ->
        by_source[source_id]
        |> Enum.take(max_per_source)
      end)
      |> Enum.take(length(articles))
    end
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

  ## Article Difficulty

  @doc """
  Calculates and stores difficulty metrics for an article.
  """
  def calculate_article_difficulty(article_id) do
    alias Langler.Content.RecommendationScorer

    article = get_article!(article_id)
    difficulty_score = RecommendationScorer.calculate_article_difficulty(article_id)

    # Calculate unique word count and average frequency
    words = RecommendationScorer.get_words_for_article(article_id)
    unique_word_count = length(words)

    words_with_freq =
      Enum.filter(words, fn word -> not is_nil(word.frequency_rank) end)

    avg_word_frequency =
      if Enum.empty?(words_with_freq) do
        nil
      else
        words_with_freq
        |> Enum.map(& &1.frequency_rank)
        |> Enum.sum()
        |> div(length(words_with_freq))
        |> then(&(&1 / 1.0))
      end

    # Calculate average sentence length
    sentences =
      Sentence
      |> where([s], s.article_id == ^article_id)
      |> select([s], s.content)
      |> Repo.all()

    avg_sentence_length =
      if Enum.empty?(sentences) do
        nil
      else
        sentences
        |> Enum.map(fn content ->
          content
          |> String.split(~r/\s+/)
          |> Enum.filter(&(&1 != ""))
          |> length()
        end)
        |> then(fn lengths ->
          if lengths == [], do: nil, else: Enum.sum(lengths) / length(lengths)
        end)
      end

    case update_article(article, %{
           difficulty_score: difficulty_score,
           unique_word_count: unique_word_count,
           avg_word_frequency: avg_word_frequency,
           avg_sentence_length: avg_sentence_length
         }) do
      {:ok, updated} -> {:ok, updated}
      error -> error
    end
  end

  @doc """
  Gets recommended articles for a user based on vocabulary level matching.
  """
  def get_recommended_articles_for_user(user_id, limit \\ 5) do
    alias Langler.Content.RecommendationScorer

    user_level = RecommendationScorer.calculate_user_level(user_id)
    numeric_level = user_level.numeric_level

    # Get discovered articles user hasn't imported yet
    DiscoveredArticle
    |> where([da], da.language == "spanish")
    |> where([da], not is_nil(da.difficulty_score))
    |> join(:left, [da], dau in DiscoveredArticleUser,
      on: dau.discovered_article_id == da.id and dau.user_id == ^user_id
    )
    |> where([da, dau], is_nil(dau.id) or dau.status == "discovered")
    |> where([da], da.difficulty_score >= ^max(numeric_level - 2, 0))
    |> where([da], da.difficulty_score <= ^min(numeric_level + 2, 10))
    |> order_by([da], desc: da.published_at)
    |> limit(^(limit * 3))
    |> Repo.all()
    |> Enum.map(&{&1, RecommendationScorer.score_discovered_article_match(&1, user_id)})
    |> Enum.sort_by(fn {_, score} -> -score end)
    |> Enum.take(limit)
    |> Enum.map(fn {article, score} -> %{article: article, score: score} end)
  end

  @doc """
  Refreshes difficulty scores for all articles.
  Admin function for recalculating all difficulties.
  """
  def refresh_article_difficulties do
    Article
    |> select([a], a.id)
    |> Repo.all()
    |> Enum.each(&calculate_article_difficulty/1)
  end

  @doc """
  Enqueues background jobs to calculate difficulty for all discovered articles.
  """
  def enqueue_difficulty_backfill do
    alias Langler.Content.Workers.CalculateArticleDifficultyWorker

    DiscoveredArticle
    |> where([da], is_nil(da.difficulty_score))
    |> select([da], da.id)
    |> Repo.all()
    |> Enum.each(fn discovered_article_id ->
      %{"discovered_article_id" => discovered_article_id}
      |> CalculateArticleDifficultyWorker.new()
      |> Oban.insert()
    end)
  end
end

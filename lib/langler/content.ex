defmodule Langler.Content do
  @moduledoc """
  Content ingestion domain for managing articles and related data.

  Handles articles, user associations, sentences, topics, and discovered articles
  for the language learning platform.
  """

  import Ecto.Query, warn: false

  alias Langler.Content.{
    Article,
    ArticleTopic,
    ArticleUser,
    DiscoveredArticle,
    DiscoveredArticleUser,
    RecommendationScorer,
    Sentence,
    SourceSite
  }

  alias Langler.Repo

  def list_articles do
    Repo.all(from a in Article, order_by: [desc: a.inserted_at])
  end

  def list_articles_for_user(user_id, opts \\ []) do
    topic = Keyword.get(opts, :topic)
    query = opts |> Keyword.get(:query) |> normalize_search_query()

    # Build base query - the topic filter join can create duplicates
    base_query =
      Article
      |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
      |> where([_a, au], au.user_id == ^user_id and au.status not in ["archived", "finished"])
      |> maybe_filter_article_topic(topic)
      |> maybe_search_articles(query)

    # Get article IDs with their sort dates, ordered correctly
    # Use window function to pick one row per article (the one with most recent date)
    article_ids_with_dates =
      base_query
      |> select([a, au], %{
        article_id: a.id,
        sort_date: fragment("COALESCE(?, ?)", au.inserted_at, a.inserted_at),
        article_inserted_at: a.inserted_at
      })
      |> order_by([a, au], [
        desc: fragment("COALESCE(?, ?)", au.inserted_at, a.inserted_at),
        desc: a.inserted_at
      ])
      |> Repo.all()
      |> Enum.reduce([], fn %{article_id: id}, acc ->
        if id in acc, do: acc, else: [id | acc]
      end)
      |> Enum.reverse()

    # Fetch full articles in the correct order
    if article_ids_with_dates == [] do
      []
    else
      articles_map =
        Article
        |> where([a], a.id in ^article_ids_with_dates)
        |> preload(:article_topics)
        |> Repo.all()
        |> Map.new(fn a -> {a.id, a} end)

      # Return articles in the original sort order
      Enum.map(article_ids_with_dates, fn id -> Map.get(articles_map, id) end)
      |> Enum.reject(&is_nil/1)
    end
  end

  def list_archived_articles_for_user(user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([_a, au], au.user_id == ^user_id and au.status == "archived")
    |> order_by([a, _], desc: a.inserted_at)
    |> Repo.all()
  end

  def list_finished_articles_for_user(user_id) do
    Article
    |> join(:inner, [a], au in ArticleUser, on: au.article_id == a.id)
    |> where([_a, au], au.user_id == ^user_id and au.status == "finished")
    |> order_by([a, _], desc: a.inserted_at)
    |> preload(:article_topics)
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

  def finish_article_for_user(user_id, article_id) do
    user_article = Repo.get_by(ArticleUser, article_id: article_id, user_id: user_id)

    case user_article do
      nil -> {:error, :not_found}
      article_user -> update_article_user(article_user, %{status: "finished"})
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

  defp normalize_search_query(nil), do: nil

  defp normalize_search_query(query) when is_binary(query) do
    query = String.trim(query)
    if query == "", do: nil, else: query
  end

  defp normalize_search_query(query), do: query |> to_string() |> normalize_search_query()

  defp maybe_search_articles(queryable, nil), do: queryable

  defp maybe_search_articles(queryable, query) when is_binary(query) do
    like = "%#{query}%"

    where(
      queryable,
      [a, _au, ...],
      ilike(a.title, ^like) or ilike(a.url, ^like) or ilike(a.source, ^like)
    )
  end

  defp maybe_filter_article_topic(queryable, nil), do: queryable
  defp maybe_filter_article_topic(queryable, ""), do: queryable

  defp maybe_filter_article_topic(queryable, topic) when is_binary(topic) do
    queryable
    |> join(:inner, [a, _au], at in ArticleTopic, on: at.article_id == a.id)
    |> where([_a, _au, at], at.topic == ^topic)
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
    # Get discovered articles first (if any) - increase pool to find better matches
    discovered = list_recommendations_for_user(user_id, limit: limit * 10)

    # Also get regular articles not imported by user (limit to reasonable number for performance)
    pool_size = limit * 50

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
        |> order_by([a], desc: a.inserted_at)
        |> limit(^pool_size)
        |> Repo.all()
      else
        Article
        |> where([a], a.id not in ^user_article_ids)
        |> preload(:article_topics)
        |> order_by([a], desc: a.inserted_at)
        |> limit(^pool_size)
        |> Repo.all()
      end

    # Build article map for regular articles (keep Article struct for scoring)
    regular_article_data =
      Enum.map(regular_articles, fn article ->
        {article_to_map(article), article}
      end)

    # Convert discovered articles to article-like maps
    # Fetch titles for articles that don't have them
    discovered_article_data =
      discovered
      |> Enum.map(fn da ->
        if da.article do
          # Already imported - use the article
          {article_to_map(da.article), da.article}
        else
          # Not yet imported - will fetch title if needed
          {nil, da}
        end
      end)
      |> fetch_titles_for_discovered_articles_with_structs()

    # Combine all articles
    all_articles = regular_article_data ++ discovered_article_data

    # Batch check which articles have words (for vocab scoring optimization)
    article_ids_with_words = batch_check_articles_with_words(all_articles)

    # Pre-compute user word frequencies and FSRS word IDs once (used for all articles)
    user_word_freqs = batch_get_user_word_frequencies(user_id)
    fsrs_word_ids = batch_get_user_fsrs_word_ids(user_id)

    # Score all articles efficiently
    scored_articles =
      all_articles
      |> Enum.map(fn {article_map, article_or_discovered} ->
        score =
          case {article_map, article_or_discovered} do
            {%{id: id}, %Article{} = article} when not is_nil(id) ->
              # Regular article - use preloaded struct
              has_words = Map.has_key?(article_ids_with_words, id)

              RecommendationScorer.score_article_for_user_optimized(
                article,
                user_id,
                has_words,
                %{topic: 0.7, vocab: 0.3},
                user_word_freqs,
                fsrs_word_ids
              )

            {article_map, _discovered} when is_map(article_map) ->
              # Discovered article - use map-based scoring
              score_discovered_article_map(article_map, user_id)

            _ ->
              # Fallback
              0.0
          end

        {article_map, score}
      end)
      |> Enum.filter(fn {_article, score} -> score > 0.1 end)
      |> Enum.sort_by(fn {_article, score} -> score end, :desc)

    # Apply source diversity and return
    select_with_source_diversity(scored_articles, limit)
    |> Enum.map(fn {article, _score} -> article end)
  end

  # Batch check which articles have words to avoid N+1 queries
  @spec batch_check_articles_with_words(list({map(), Article.t() | nil})) ::
          %{optional(integer()) => true}
  defp batch_check_articles_with_words(all_articles) do
    article_ids =
      all_articles
      |> Enum.flat_map(fn {article_map, article_or_discovered} ->
        case {article_map, article_or_discovered} do
          {%{id: id}, %Article{}} when not is_nil(id) -> [id]
          _ -> []
        end
      end)
      |> Enum.uniq()

    if Enum.empty?(article_ids) do
      %{}
    else
      Sentence
      |> where([s], s.article_id in ^article_ids)
      |> select([s], s.article_id)
      |> distinct([s], s.article_id)
      |> Repo.all()
      |> Enum.reduce(%{}, fn id, acc -> Map.put(acc, id, true) end)
    end
  end

  # Batch get user word frequencies (used for all articles)
  defp batch_get_user_word_frequencies(user_id) do
    alias Langler.Content.RecommendationScorer
    RecommendationScorer.get_user_word_frequencies(user_id)
  end

  # Batch get user FSRS word IDs (used for all articles)
  defp batch_get_user_fsrs_word_ids(user_id) do
    alias Langler.Content.RecommendationScorer
    RecommendationScorer.get_user_fsrs_word_ids(user_id)
  end

  # Select articles ensuring source diversity
  # Limits articles per source and uses round-robin to ensure variety
  defp select_with_source_diversity(scored_articles, limit) do
    # Group by source, keeping articles sorted by score within each source
    by_source =
      scored_articles
      |> Enum.group_by(fn {article, _score} ->
        get_article_source(article)
      end)
      |> Map.new(fn {source, articles} ->
        {source, Enum.sort_by(articles, fn {_article, score} -> score end, :desc)}
      end)

    num_sources = map_size(by_source)

    # If only one source or very few articles, just take top N
    if num_sources <= 1 or length(scored_articles) <= limit do
      Enum.take(scored_articles, limit)
    else
      # Calculate max per source (limit to 2-3 max to ensure diversity)
      max_per_source = min(3, max(1, div(limit, num_sources) + 1))

      # Round-robin: take articles from each source in turn
      sources = Map.keys(by_source) |> Enum.shuffle()
      select_diverse_round_robin(by_source, sources, max_per_source, limit, [])
    end
  end

  defp select_diverse_round_robin(by_source, sources, max_per_source, limit, acc) do
    # Base cases
    cond do
      limit <= 0 -> acc
      sources == [] -> acc
      true -> process_round_robin_round(by_source, sources, max_per_source, limit, acc)
    end
  end

  defp process_round_robin_round(by_source, sources, max_per_source, limit, acc) do
    # Take articles from each source in round-robin fashion
    {new_selected, updated_by_source, active_sources} =
      Enum.reduce(sources, {[], by_source, []}, fn source, state ->
        take_from_source(source, state, max_per_source)
      end)

    # Add selected to accumulator, limiting to what we need
    new_acc = acc ++ Enum.take(new_selected, limit)
    new_remaining = limit - length(new_selected)

    # Continue if we need more and have active sources
    if new_remaining > 0 and active_sources != [] do
      select_diverse_round_robin(
        updated_by_source,
        active_sources,
        max_per_source,
        new_remaining,
        new_acc
      )
    else
      new_acc
    end
  end

  defp take_from_source(source, {selected, by_source_acc, active_acc}, max_per_source) do
    source_articles = Map.get(by_source_acc, source, [])

    if source_articles == [] do
      {selected, by_source_acc, active_acc}
    else
      {to_take, remaining} = Enum.split(source_articles, max_per_source)
      updated_by_source = update_source_map(by_source_acc, source, remaining)
      updated_active = update_active_sources(active_acc, source, remaining)

      {selected ++ to_take, updated_by_source, updated_active}
    end
  end

  defp update_source_map(by_source_acc, source, []), do: Map.delete(by_source_acc, source)

  defp update_source_map(by_source_acc, source, remaining),
    do: Map.put(by_source_acc, source, remaining)

  defp update_active_sources(active, _source, []), do: active
  defp update_active_sources(active, source, _remaining), do: active ++ [source]

  defp get_article_source(%{source: source}) when is_binary(source) and source != "", do: source
  defp get_article_source(%{url: url}) when is_binary(url), do: extract_source_from_url(url)
  defp get_article_source(_), do: :unknown

  defp extract_source_from_url(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  # Score a discovered article map using text classification
  defp score_discovered_article_map(article_map, user_id) do
    # Build a minimal DiscoveredArticle struct for scoring
    discovered = %DiscoveredArticle{
      title: article_map.title,
      summary: article_map.content,
      language: article_map.language,
      difficulty_score: article_map.difficulty_score
    }

    RecommendationScorer.score_discovered_article_match(discovered, user_id)
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

  # Fetch titles for discovered articles, handling new structure with Article structs
  defp fetch_titles_for_discovered_articles_with_structs(discovered_with_data) do
    {needs_fetch, already_mapped} = separate_discovered_by_fetch_needs(discovered_with_data)

    fetched_titles = fetch_titles_if_needed_for_discovered(needs_fetch)

    updated_needs_fetch =
      build_article_maps_from_fetched_with_structs(needs_fetch, fetched_titles)

    already_mapped_data = extract_valid_article_data(already_mapped)

    already_mapped_data ++ updated_needs_fetch
  end

  defp separate_discovered_by_fetch_needs(discovered_with_data) do
    Enum.split_with(discovered_with_data, fn
      {article_map, %Article{}} when is_map(article_map) -> false
      {nil, %DiscoveredArticle{} = da} -> is_nil(da.title) or da.title == ""
      {_article_map, %DiscoveredArticle{} = da} -> is_nil(da.title) or da.title == ""
      _ -> false
    end)
  end

  defp fetch_titles_if_needed_for_discovered([]), do: %{}

  defp fetch_titles_if_needed_for_discovered(needs_fetch) do
    needs_fetch
    |> Enum.flat_map(fn {_article_map, %DiscoveredArticle{} = da} -> [da.url] end)
    |> Enum.uniq()
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

  defp build_article_maps_from_fetched_with_structs(needs_fetch, fetched_titles) do
    Enum.map(needs_fetch, fn {_article_map, %DiscoveredArticle{} = da} ->
      article_map = build_article_map_from_discovered(da, fetched_titles)
      {article_map, da}
    end)
  end

  defp build_article_map_from_discovered(da, fetched_titles) do
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
  end

  defp extract_valid_article_data(already_mapped) do
    already_mapped
    |> Enum.map(fn {article_map, article_or_discovered} ->
      if is_map(article_map) do
        {article_map, article_or_discovered}
      else
        nil
      end
    end)
    |> Enum.filter(&(not is_nil(&1)))
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
    case Floki.parse_document(html) do
      {:ok, document} -> extract_title_from_document(document)
      _ -> {:error, :parse_failed}
    end
  end

  defp extract_title_from_document(document) do
    title = extract_title_tag(document)

    if title != "" do
      {:ok, title}
    else
      h1_title = extract_h1_from_document(document)
      extract_h1_title(h1_title)
    end
  end

  defp extract_title_tag(document) do
    document
    |> Floki.find("title")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_h1_from_document(document) do
    document
    |> Floki.find("h1")
    |> Enum.at(0)
    |> case do
      nil -> nil
      h1 -> Floki.text(h1) |> String.trim()
    end
  end

  defp extract_h1_title(nil), do: {:error, :no_title}
  defp extract_h1_title(""), do: {:error, :no_title}
  defp extract_h1_title(title), do: {:ok, title}

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
        build_discovered_article_entry(attrs, source_site_id, now)
      end)

    # Use on_conflict to update title and summary if they're missing or changed
    Repo.insert_all(DiscoveredArticle, entries,
      on_conflict: {:replace_all_except, [:id, :inserted_at, :article_id, :status]},
      conflict_target: [:source_site_id, :url]
    )
  end

  defp build_discovered_article_entry(attrs, source_site_id, now) do
    discovered_at = normalize_discovered_at(attrs, now)
    published_at = normalize_published_at(attrs)

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
  end

  defp normalize_discovered_at(attrs, default) do
    discovered = attrs[:discovered_at] || attrs["discovered_at"]

    if discovered do
      if is_struct(discovered, DateTime),
        do: DateTime.truncate(discovered, :second),
        else: default
    else
      default
    end
  end

  defp normalize_published_at(attrs) do
    pub = attrs[:published_at] || attrs["published_at"]

    if pub do
      if is_struct(pub, DateTime), do: DateTime.truncate(pub, :second), else: nil
    else
      nil
    end
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

    avg_sentence_length = calculate_avg_sentence_length(sentences)

    update_article(article, %{
      difficulty_score: difficulty_score,
      unique_word_count: unique_word_count,
      avg_word_frequency: avg_word_frequency,
      avg_sentence_length: avg_sentence_length
    })
  end

  defp calculate_avg_sentence_length(sentences) do
    if Enum.empty?(sentences) do
      nil
    else
      lengths =
        sentences
        |> Enum.map(fn content ->
          content
          |> String.split(~r/\s+/)
          |> Enum.filter(&(&1 != ""))
          |> length()
        end)

      if lengths == [], do: nil, else: Enum.sum(lengths) / length(lengths)
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

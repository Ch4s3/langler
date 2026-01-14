defmodule Langler.Content.RecommendationScorer do
  @moduledoc """
  Enhanced recommendation scoring that combines topic preferences and vocabulary novelty.
  """

  import Ecto.Query, warn: false
  alias Langler.Repo
  alias Langler.Content.Article
  alias Langler.Vocabulary.{Word, WordOccurrence}
  alias Langler.Study.FSRSItem
  alias Langler.Accounts

  @default_weights %{topic: 0.7, vocab: 0.3}
  @vocab_novelty_threshold 3

  @doc """
  Scores an article for a user combining topic match and vocabulary novelty.
  For articles without extracted words (e.g., discovered but not imported), only uses topic score.
  """
  @spec score_article_for_user(Article.t(), integer(), map()) :: float()
  def score_article_for_user(%Article{} = article, user_id, weights \\ @default_weights) do
    topic_score = calculate_topic_score(article, user_id)

    # Only calculate vocab score if article has words extracted
    vocab_score =
      if has_words?(article.id) do
        calculate_vocabulary_novelty(article, user_id)
      else
        0.0
      end

    # If no vocab score available, weight topic score more
    effective_weights =
      if vocab_score == 0.0 do
        %{topic: 1.0, vocab: 0.0}
      else
        weights
      end

    (topic_score * effective_weights.topic) + (vocab_score * effective_weights.vocab)
  end

  defp has_words?(article_id) do
    Langler.Content.Sentence
    |> where([s], s.article_id == ^article_id)
    |> select([s], count(s.id))
    |> Repo.one() > 0
  end

  @doc """
  Calculates topic-based score for an article.
  """
  @spec calculate_topic_score(Article.t(), integer()) :: float()
  def calculate_topic_score(%Article{} = article, user_id) do
    user_topics = Accounts.get_user_topic_preferences(user_id)
    article_topics = Langler.Content.list_topics_for_article(article.id)

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
  Calculates vocabulary novelty score for an article.
  Words seen < 3 times and not in FSRS study list are considered novel.
  """
  @spec calculate_vocabulary_novelty(Article.t(), integer()) :: float()
  def calculate_vocabulary_novelty(%Article{} = article, user_id) do
    article_words = get_words_for_article(article.id)
    user_word_freqs = get_user_word_frequencies(user_id)
    fsrs_word_ids = get_user_fsrs_word_ids(user_id)

    if Enum.empty?(article_words) do
      0.0
    else
      total =
        Enum.reduce(article_words, 0.0, fn word, acc ->
          freq = Map.get(user_word_freqs, word.id, 0)
          in_fsrs = word.id in fsrs_word_ids

          cond do
            freq == 0 -> acc + 1.0
            freq < @vocab_novelty_threshold and not in_fsrs -> acc + 0.5
            freq < @vocab_novelty_threshold and in_fsrs -> acc + 0.2
            true -> acc
          end
        end)

      total / max(length(article_words), 1)
    end
  end

  # Get all unique words from an article via word_occurrences
  defp get_words_for_article(article_id) do
    sentence_ids =
      Langler.Content.Sentence
      |> where([s], s.article_id == ^article_id)
      |> select([s], s.id)
      |> Repo.all()

    if Enum.empty?(sentence_ids) do
      []
    else
      WordOccurrence
      |> join(:inner, [wo], w in Word, on: wo.word_id == w.id)
      |> where([wo, w], wo.sentence_id in ^sentence_ids)
      |> distinct([wo, w], w.id)
      |> select([wo, w], w)
      |> Repo.all()
    end
  end

  # Count word occurrences across user's imported articles
  defp get_user_word_frequencies(user_id) do
    # Get all article IDs for this user
    user_article_ids =
      Langler.Content.ArticleUser
      |> where([au], au.user_id == ^user_id and au.status != "archived")
      |> select([au], au.article_id)
      |> Repo.all()

    if Enum.empty?(user_article_ids) do
      %{}
    else
      WordOccurrence
      |> join(:inner, [wo], s in Langler.Content.Sentence, on: wo.sentence_id == s.id)
      |> where([wo, s], s.article_id in ^user_article_ids)
      |> group_by([wo], wo.word_id)
      |> select([wo], {wo.word_id, count(wo.id)})
      |> Repo.all()
      |> Map.new()
    end
  end

  # Get word IDs from user's FSRS items
  defp get_user_fsrs_word_ids(user_id) do
    FSRSItem
    |> where([fi], fi.user_id == ^user_id)
    |> select([fi], fi.word_id)
    |> Repo.all()
    |> MapSet.new()
  end
end

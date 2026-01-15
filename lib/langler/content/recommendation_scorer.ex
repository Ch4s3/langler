defmodule Langler.Content.RecommendationScorer do
  @moduledoc """
  Enhanced recommendation scoring that combines topic preferences and vocabulary novelty.
  """

  import Ecto.Query, warn: false
  alias Langler.Repo
  alias Langler.Content.{Article, Sentence, DiscoveredArticle}
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

    topic_score * effective_weights.topic + vocab_score * effective_weights.vocab
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
        acc + confidence * weight
      end)

    # Add freshness bonus (newer articles get slight boost)
    days_old = DateTime.diff(DateTime.utc_now(), article.inserted_at, :day)
    freshness_bonus = max(0.0, 1.0 - days_old / 30.0) * 0.1

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
  def get_words_for_article(article_id) do
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

  @doc """
  Calculates article difficulty combining vocabulary frequency (70%) and readability (30%).
  Returns a score from 0.0 (easiest) to 10.0 (hardest).
  """
  @spec calculate_article_difficulty(integer()) :: float()
  def calculate_article_difficulty(article_id) do
    article_words = get_words_for_article(article_id)

    if Enum.empty?(article_words) do
      5.0
    else
      vocab_score = calculate_vocabulary_difficulty(article_words)
      readability_score = calculate_readability_difficulty(article_id)

      vocab_score * 0.7 + readability_score * 0.3
    end
  end

  defp calculate_vocabulary_difficulty(words) do
    # Filter words with frequency_rank
    words_with_freq =
      Enum.filter(words, fn word -> not is_nil(word.frequency_rank) end)

    if Enum.empty?(words_with_freq) do
      5.0
    else
      # Calculate average frequency rank
      avg_rank =
        words_with_freq
        |> Enum.map(& &1.frequency_rank)
        |> Enum.sum()
        |> div(length(words_with_freq))

      # Convert frequency rank to difficulty score (0-10)
      # Lower rank = more common = easier
      # Higher rank = rarer = harder
      # Scale: rank 1-1000 (A1) = 0-2, 1001-2000 (A2) = 2-4, etc.
      case avg_rank do
        rank when rank <= 1000 -> rank / 500.0
        rank when rank <= 2000 -> 2.0 + (rank - 1000) / 500.0
        rank when rank <= 3500 -> 4.0 + (rank - 2000) / 500.0
        rank when rank <= 5000 -> 7.0 + (rank - 3500) / 500.0
        _ -> 10.0
      end
      |> min(10.0)
      |> max(0.0)
    end
  end

  defp calculate_readability_difficulty(article_id) do
    sentences =
      Sentence
      |> where([s], s.article_id == ^article_id)
      |> select([s], s.content)
      |> Repo.all()

    if Enum.empty?(sentences) do
      5.0
    else
      # Calculate average sentence length (words per sentence)
      avg_length =
        sentences
        |> Enum.map(fn content ->
          content
          |> String.split(~r/\s+/)
          |> Enum.filter(&(&1 != ""))
          |> length()
        end)
        |> then(fn lengths ->
          if lengths == [], do: 0, else: Enum.sum(lengths) / length(lengths)
        end)

      # Normalize to 0-10 scale
      case avg_length do
        len when len < 10 -> 0.0
        len when len < 15 -> 3.0
        len when len < 20 -> 5.0
        len when len < 25 -> 7.0
        _ -> 10.0
      end
    end
  end

  @doc """
  Calculates user's vocabulary level based on their FSRS study items.
  Returns %{cefr_level: "A1" | "A2" | "B1" | "B2" | "C1" | "C2", numeric_level: float()}
  Defaults to A1 / 1.0 for new users with no study history.
  """
  @spec calculate_user_level(integer()) :: %{cefr_level: String.t(), numeric_level: float()}
  def calculate_user_level(user_id) do
    items =
      FSRSItem
      |> where([fi], fi.user_id == ^user_id)
      |> preload(:word)
      |> Repo.all()
      |> Enum.filter(fn item -> not is_nil(item.word) end)

    if Enum.empty?(items) do
      %{cefr_level: "A1", numeric_level: 1.0}
    else
      # Get words with frequency ranks
      words_with_freq =
        items
        |> Enum.map(& &1.word)
        |> Enum.filter(fn word -> not is_nil(word.frequency_rank) end)

      if Enum.empty?(words_with_freq) do
        %{cefr_level: "A1", numeric_level: 1.0}
      else
        # Calculate average frequency rank
        avg_rank =
          words_with_freq
          |> Enum.map(& &1.frequency_rank)
          |> Enum.sum()
          |> div(length(words_with_freq))

        # Determine CEFR level from average rank
        {cefr_level, numeric_level} =
          case avg_rank do
            rank when rank <= 1000 -> {"A1", 1.0 + rank / 1000.0}
            rank when rank <= 2000 -> {"A2", 2.0 + (rank - 1000) / 1000.0}
            rank when rank <= 3500 -> {"B1", 3.5 + (rank - 2000) / 1500.0}
            rank when rank <= 5000 -> {"B2", 5.0 + (rank - 3500) / 1500.0}
            rank when rank <= 10000 -> {"C1", 7.0 + (rank - 5000) / 5000.0}
            _rank -> {"C2", 9.0}
          end

        %{cefr_level: cefr_level, numeric_level: min(numeric_level, 10.0)}
      end
    end
  end

  @doc """
  Scores a discovered article match for a user.
  Combines level match (40%), vocabulary novelty (30%), topic preference (20%), and progressive challenge (10%).
  """
  @spec score_discovered_article_match(DiscoveredArticle.t(), integer()) :: float()
  def score_discovered_article_match(%DiscoveredArticle{} = article, user_id) do
    user_level = calculate_user_level(user_id)
    article_difficulty = article.difficulty_score || 5.0

    # Level match (40%): Penalize if too easy or too hard
    level_match_score =
      diff = abs(article_difficulty - user_level.numeric_level)

    cond do
      diff <= 0.5 -> 1.0
      diff <= 1.0 -> 0.8
      diff <= 2.0 -> 0.5
      diff <= 3.0 -> 0.2
      true -> 0.0
    end

    # Vocabulary novelty (30%): Use existing logic if article has been analyzed
    vocab_novelty_score =
      if article.difficulty_score do
        # If difficulty is calculated, estimate novelty from difficulty
        # Articles slightly above user level have good novelty
        novelty_diff = article_difficulty - user_level.numeric_level

        cond do
          novelty_diff > 0 and novelty_diff <= 1.5 -> 1.0
          novelty_diff > 1.5 and novelty_diff <= 2.5 -> 0.7
          novelty_diff > 2.5 -> 0.3
          novelty_diff < 0 -> 0.5
          true -> 0.8
        end
      else
        0.5
      end

    # Topic preference (20%): Use existing topic scoring
    topic_score =
      try do
        # Try to get topic score if article has topics
        # For discovered articles, we may not have topics yet
        calculate_topic_score_for_discovered(article, user_id)
      rescue
        _ -> 0.5
      end

    # Progressive challenge (10%): Bonus for articles slightly above current level
    challenge_bonus =
      diff = article_difficulty - user_level.numeric_level

    cond do
      diff > 0 and diff <= 1.0 -> 1.0
      diff > 1.0 and diff <= 2.0 -> 0.7
      diff > 2.0 -> 0.3
      true -> 0.5
    end

    level_match_score * 0.4 + vocab_novelty_score * 0.3 + topic_score * 0.2 +
      challenge_bonus * 0.1
  end

  defp calculate_topic_score_for_discovered(%DiscoveredArticle{} = _article, _user_id) do
    # For discovered articles, we may not have topic data yet
    # Return neutral score for now
    # TODO: Extract topics from discovered articles if available
    0.5
  end

  @doc """
  Calculates difficulty for a discovered article using title and summary.
  Since discovered articles don't have full content yet, this is an estimate.
  """
  @spec calculate_discovered_article_difficulty(DiscoveredArticle.t()) :: float()
  def calculate_discovered_article_difficulty(%DiscoveredArticle{} = article) do
    # Combine title and summary for analysis
    text =
      [article.title, article.summary]
      |> Enum.filter(&(&1 && &1 != ""))
      |> Enum.join(" ")

    if text == "" do
      5.0
    else
      # Tokenize the text
      words =
        text
        |> String.downcase()
        |> String.split(~r/\W+/u)
        |> Enum.filter(&(&1 != ""))

      if Enum.empty?(words) do
        5.0
      else
        # Look up words in database to get frequency ranks
        normalized_words = Enum.map(words, &Langler.Vocabulary.normalize_form/1)

        words_with_freq =
          Word
          |> where([w], w.normalized_form in ^normalized_words and w.language == "spanish")
          |> where([w], not is_nil(w.frequency_rank))
          |> Repo.all()

        vocab_score =
          if Enum.empty?(words_with_freq) do
            5.0
          else
            avg_rank =
              words_with_freq
              |> Enum.map(& &1.frequency_rank)
              |> Enum.sum()
              |> div(length(words_with_freq))

            case avg_rank do
              rank when rank <= 1000 -> rank / 500.0
              rank when rank <= 2000 -> 2.0 + (rank - 1000) / 500.0
              rank when rank <= 3500 -> 4.0 + (rank - 2000) / 500.0
              rank when rank <= 5000 -> 7.0 + (rank - 3500) / 500.0
              _ -> 10.0
            end
            |> min(10.0)
            |> max(0.0)
          end

        # Readability from sentence count in title+summary
        sentences =
          text
          |> String.split(~r/[.!?]+/)
          |> Enum.filter(&(&1 != "" && String.trim(&1) != ""))

        readability_score =
          if Enum.empty?(sentences) do
            5.0
          else
            avg_length = length(words) / max(length(sentences), 1)

            case avg_length do
              len when len < 10 -> 0.0
              len when len < 15 -> 3.0
              len when len < 20 -> 5.0
              len when len < 25 -> 7.0
              _ -> 10.0
            end
          end

        vocab_score * 0.7 + readability_score * 0.3
      end
    end
  end
end

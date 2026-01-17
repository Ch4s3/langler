defmodule Langler.Content.RecommendationScorerTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures
  import Langler.ContentFixtures
  import Langler.StudyFixtures
  import Langler.VocabularyFixtures

  alias Langler.Content.DiscoveredArticle
  alias Langler.Content.RecommendationScorer

  test "calculate_user_level/1 defaults for new users" do
    user = user_fixture()

    assert %{cefr_level: "A1", numeric_level: 1.0} =
             RecommendationScorer.calculate_user_level(user.id)
  end

  test "calculate_user_level/1 uses frequency ranks when available" do
    user = user_fixture()
    word = word_fixture(%{frequency_rank: 500})
    fsrs_item_fixture(%{user: user, word: word})

    level = RecommendationScorer.calculate_user_level(user.id)

    assert level.cefr_level == "A1"
    assert level.numeric_level > 1.0
  end

  test "calculate_discovered_article_difficulty/1 handles empty and populated text" do
    empty = %DiscoveredArticle{title: "", summary: ""}
    assert RecommendationScorer.calculate_discovered_article_difficulty(empty) == 5.0

    article = %DiscoveredArticle{title: "Hola mundo", summary: nil}
    assert is_number(RecommendationScorer.calculate_discovered_article_difficulty(article))
  end

  test "calculate_article_difficulty/1 returns default when no words exist" do
    article = article_fixture()

    assert RecommendationScorer.calculate_article_difficulty(article.id) == 5.0
  end

  test "get_words_for_article/1 returns distinct words" do
    article = article_fixture()
    sentence = sentence_fixture(article)
    word = word_fixture(%{frequency_rank: 1200})
    occurrence_fixture(%{sentence: sentence, word: word})

    words = RecommendationScorer.get_words_for_article(article.id)

    assert Enum.any?(words, &(&1.id == word.id))
  end

  test "calculate_vocabulary_novelty/2 returns full novelty for unseen words" do
    article = article_fixture()
    sentence = sentence_fixture(article)
    word = word_fixture()
    occurrence_fixture(%{sentence: sentence, word: word})

    other_user = user_fixture()

    assert RecommendationScorer.calculate_vocabulary_novelty(article, other_user.id) == 1.0
  end

  test "score_article_for_user/3 combines topic and vocab scores" do
    user = user_fixture()
    article = article_fixture()
    sentence = sentence_fixture(article)
    word = word_fixture()
    occurrence_fixture(%{sentence: sentence, word: word})

    # Set topic preference
    Langler.Accounts.set_user_topic_preference(user.id, "ciencia", 1.5)
    Langler.Content.tag_article(article, [{"ciencia", 0.8}])

    score = RecommendationScorer.score_article_for_user(article, user.id)
    assert is_float(score)
    assert score > 0.0
  end

  test "score_article_for_user/3 uses only topic score when no words" do
    user = user_fixture()
    article = article_fixture()

    Langler.Accounts.set_user_topic_preference(user.id, "ciencia", 1.5)
    Langler.Content.tag_article(article, [{"ciencia", 0.8}])

    score = RecommendationScorer.score_article_for_user(article, user.id)
    assert is_float(score)
    assert score > 0.0
  end

  test "calculate_topic_score/2 includes freshness bonus" do
    user = user_fixture()
    article = article_fixture(%{inserted_at: DateTime.utc_now()})

    Langler.Accounts.set_user_topic_preference(user.id, "ciencia", 1.0)
    Langler.Content.tag_article(article, [{"ciencia", 0.9}])

    score = RecommendationScorer.calculate_topic_score(article, user.id)
    assert score > 0.0
  end

  test "calculate_topic_score/2 handles articles without topics" do
    user = user_fixture()
    article = article_fixture()

    score = RecommendationScorer.calculate_topic_score(article, user.id)
    assert is_float(score)
  end

  test "calculate_vocabulary_novelty/2 handles words with different frequencies" do
    user = user_fixture()
    article = article_fixture()
    sentence = sentence_fixture(article)

    # Create words with different frequencies
    word1 = word_fixture()
    word2 = word_fixture()
    word3 = word_fixture()

    occurrence_fixture(%{sentence: sentence, word: word1})
    occurrence_fixture(%{sentence: sentence, word: word2})
    occurrence_fixture(%{sentence: sentence, word: word3})

    # User has seen word2 multiple times
    user_article = article_fixture()
    user_sentence = sentence_fixture(user_article)
    occurrence_fixture(%{sentence: user_sentence, word: word2})
    occurrence_fixture(%{sentence: user_sentence, word: word2})
    occurrence_fixture(%{sentence: user_sentence, word: word2})
    Langler.Content.ensure_article_user(user_article, user.id)

    score = RecommendationScorer.calculate_vocabulary_novelty(article, user.id)
    assert is_float(score)
    assert score >= 0.0
    assert score <= 1.0
  end

  test "calculate_vocabulary_novelty/2 handles words in FSRS" do
    user = user_fixture()
    article = article_fixture()
    sentence = sentence_fixture(article)
    word = word_fixture()
    occurrence_fixture(%{sentence: sentence, word: word})

    # Add word to FSRS
    fsrs_item_fixture(%{user: user, word: word})

    score = RecommendationScorer.calculate_vocabulary_novelty(article, user.id)
    assert is_float(score)
  end

  test "calculate_article_difficulty/1 with words and sentences" do
    article = article_fixture()

    sentence =
      sentence_fixture(article, %{content: "Esta es una oración de prueba con varias palabras."})

    word = word_fixture(%{frequency_rank: 1500})
    occurrence_fixture(%{sentence: sentence, word: word})

    difficulty = RecommendationScorer.calculate_article_difficulty(article.id)
    assert is_float(difficulty)
    assert difficulty >= 0.0
    assert difficulty <= 10.0
  end

  test "calculate_user_level/1 with different frequency ranks" do
    user = user_fixture()

    # A2 level word
    word1 = word_fixture(%{frequency_rank: 1500})
    fsrs_item_fixture(%{user: user, word: word1})

    # B1 level word
    word2 = word_fixture(%{frequency_rank: 3000})
    fsrs_item_fixture(%{user: user, word: word2})

    level = RecommendationScorer.calculate_user_level(user.id)
    assert level.cefr_level in ["A1", "A2", "B1", "B2", "C1", "C2"]
    assert level.numeric_level >= 1.0
  end

  test "score_discovered_article_match/2 scores discovered articles" do
    user = user_fixture()
    word = word_fixture(%{frequency_rank: 1000})
    fsrs_item_fixture(%{user: user, word: word})

    discovered = %Langler.Content.DiscoveredArticle{
      title: "Test Article",
      summary: "This is a test summary",
      difficulty_score: 3.0,
      language: "spanish"
    }

    score = RecommendationScorer.score_discovered_article_match(discovered, user.id)
    assert is_float(score)
    assert score >= 0.0
  end

  test "calculate_discovered_article_difficulty/1 with title and summary" do
    article = %Langler.Content.DiscoveredArticle{
      title: "Ciencia y tecnología avanzan rápidamente",
      summary: "Los científicos descubren nuevas tecnologías cada día.",
      language: "spanish"
    }

    difficulty = RecommendationScorer.calculate_discovered_article_difficulty(article)
    assert is_float(difficulty)
    assert difficulty >= 0.0
    assert difficulty <= 10.0
  end
end

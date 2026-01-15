defmodule Langler.Content.Classifier do
  @moduledoc """
  Topic classifier for articles.
  Uses ML (TF-IDF + Naive Bayes) when available, falls back to rule-based keyword matching.
  """

  alias Langler.Content.Topics
  alias Langler.Content.ClassifierNif
  alias Langler.Repo
  alias Langler.Content.{Article, ArticleTopic}
  import Ecto.Query

  @confidence_threshold 0.15
  @default_max_topics 3
  @model_table :classifier_model

  @doc """
  Classifies article content into topics based on keyword matching.

  Returns a list of `{topic_id, confidence}` tuples sorted by confidence descending.

  ## Examples

      iex> classify("La ciencia busca nuevas respuestas", "spanish")
      [{"ciencia", 0.45}, {"sociedad", 0.12}]

      iex> classify("The government announced new policies", "english")
      [{"politics", 0.52}]
  """
  @spec classify(String.t(), String.t()) :: list({String.t(), float()})
  def classify(content, language \\ "spanish")

  def classify(content, language) when is_binary(content) and is_binary(language) do
    if String.trim(content) == "" do
      []
    else
      # Try ML classifier first, fallback to rule-based
      case classify_with_ml(content, language) do
        {:ok, topics} when topics != [] ->
          topics

        _ ->
          # Fallback to rule-based
          classify_rule_based(content, language)
      end
    end
  end

  def classify(_, _), do: []

  # ML-based classification using TF-IDF + Naive Bayes
  defp classify_with_ml(content, language) do
    case get_model(language) do
      {:ok, model_json} ->
        case ClassifierNif.classify(content, model_json) do
          result when is_map(result) ->
            topics =
              result
              |> Map.get("topics", [])
              |> Enum.map(fn topic_map ->
                topic = Map.get(topic_map, "topic") || Map.get(topic_map, :topic)

                conf =
                  Map.get(topic_map, "confidence", 0.0) || Map.get(topic_map, :confidence, 0.0)

                {topic, conf}
              end)
              |> Enum.filter(fn {_topic, conf} ->
                is_float(conf) and conf >= @confidence_threshold
              end)
              |> Enum.sort_by(fn {_topic, conf} -> conf end, :desc)
              |> Enum.take(@default_max_topics)

            {:ok, topics}

          {:error, :nif_not_loaded} ->
            {:error, :nif_not_loaded}

          other ->
            {:error, other}
        end

      {:error, _} ->
        {:error, :no_model}
    end
  end

  # Rule-based classification (original implementation)
  defp classify_rule_based(content, language) do
    content
    |> normalize_content()
    |> tokenize()
    |> score_topics(language)
    |> filter_by_threshold(@confidence_threshold)
    |> sort_by_confidence()
    |> take_top(@default_max_topics)
  end

  @doc """
  Trains the ML classifier on labeled articles.
  Training data format: [%{"content" => "...", "topics" => ["topic1", ...]}, ...]
  """
  @spec train(list(map()), String.t()) :: {:ok, String.t()} | {:error, term()}
  def train(training_data, language \\ "spanish") when is_list(training_data) do
    if length(training_data) < 10 do
      {:error, :insufficient_training_data}
    else
      # Prepare training data for Rust NIF (use atom keys for rustler compatibility)
      formatted_data =
        Enum.map(training_data, fn doc ->
          %{
            content: Map.get(doc, "content") || Map.get(doc, :content) || "",
            topics: Map.get(doc, "topics") || Map.get(doc, :topics) || []
          }
        end)

      case ClassifierNif.train(formatted_data) do
        model_json when is_binary(model_json) ->
          # Store model in ETS
          store_model(language, model_json)
          {:ok, model_json}

        {:error, :nif_not_loaded} ->
          {:error, :nif_not_loaded}

        other ->
          {:error, other}
      end
    end
  end

  @doc """
  Collects training data from existing articles with high-confidence topic assignments.
  Returns training data ready for ML classifier training.
  """
  @spec collect_training_data(integer(), float()) :: list(map())
  def collect_training_data(min_confidence \\ 0.7, limit \\ 1000) do
    alias Langler.Repo
    alias Langler.Content.ArticleTopic
    alias Langler.Content.Article
    import Ecto.Query

    # Get articles with high-confidence topic assignments
    articles =
      Article
      |> join(:inner, [a], at in ArticleTopic, on: at.article_id == a.id)
      |> where([a, at], at.confidence >= ^min_confidence)
      |> group_by([a, at], a.id)
      |> having([a, at], count(at.id) > 0)
      |> limit(^limit)
      |> preload(:article_topics)
      |> Repo.all()

    Enum.map(articles, fn article ->
      topics =
        article.article_topics
        |> Enum.filter(&(&1.confidence >= min_confidence))
        |> Enum.map(& &1.topic)

      %{
        "content" => article.content || "",
        "topics" => topics
      }
    end)
    |> Enum.filter(fn doc -> length(doc["topics"]) > 0 end)
  end

  # Get model from ETS
  defp get_model(language) do
    ensure_ets_table()

    case :ets.lookup(@model_table, language) do
      [{^language, model_json}] -> {:ok, model_json}
      [] -> {:error, :not_found}
    end
  end

  # Store model in ETS
  defp store_model(language, model_json) do
    ensure_ets_table()
    :ets.insert(@model_table, {language, model_json})
  end

  # Ensure ETS table exists
  defp ensure_ets_table do
    case :ets.whereis(@model_table) do
      :undefined ->
        :ets.new(@model_table, [:named_table, :public, :set])

      _pid ->
        :ok
    end
  end

  # Normalize content: lowercase, remove accents for matching
  defp normalize_content(content) do
    content
    |> String.downcase()
    |> remove_accents()
  end

  # Simple accent removal for Spanish/Portuguese
  defp remove_accents(text) do
    text
    |> String.replace("á", "a")
    |> String.replace("é", "e")
    |> String.replace("í", "i")
    |> String.replace("ó", "o")
    |> String.replace("ú", "u")
    |> String.replace("ñ", "n")
    |> String.replace("ü", "u")
  end

  # Tokenize into words (split on whitespace and punctuation)
  defp tokenize(content) do
    content
    |> String.split(~r/[^\p{L}\p{N}]+/u)
    |> Enum.filter(&(&1 != ""))
  end

  # Score each topic based on keyword matches
  defp score_topics(tokens, language) do
    topics = Topics.topics_for_language(language)
    total_words = length(tokens)
    token_set = MapSet.new(tokens)

    topics
    |> Enum.map(fn {topic_id, topic_config} ->
      score = calculate_topic_score(topic_config, token_set, total_words)
      {to_string(topic_id), score}
    end)
    |> Enum.filter(fn {_topic_id, score} -> score > 0.0 end)
  end

  # Calculate score for a single topic
  defp calculate_topic_score(topic_config, token_set, total_words) do
    keywords = topic_config.keywords
    weight = topic_config.weight

    normalized_keywords =
      keywords
      |> Enum.map(&String.downcase/1)
      |> Enum.map(&remove_accents/1)

    matches = Enum.count(normalized_keywords, &MapSet.member?(token_set, &1))

    if total_words > 0 and matches > 0 do
      # Base score: matches per word (higher is better)
      base_score = matches / total_words
      # Keyword density: how many of the topic's keywords matched (higher is better)
      keyword_density = matches / length(keywords)
      # Boost score based on number of matches (more matches = stronger signal)
      # Cap boost at 3 matches
      match_boost = min(matches / 3.0, 1.0)

      # Combine scores with boost
      score = base_score * 0.5 + keyword_density * 0.3 + match_boost * 0.2
      score * weight
    else
      0.0
    end
  end

  # Filter topics below confidence threshold
  defp filter_by_threshold(scored_topics, threshold) do
    Enum.filter(scored_topics, fn {_topic_id, confidence} ->
      confidence >= threshold
    end)
  end

  # Sort by confidence descending
  defp sort_by_confidence(scored_topics) do
    Enum.sort_by(scored_topics, fn {_topic_id, confidence} -> confidence end, :desc)
  end

  # Take top N topics
  defp take_top(scored_topics, limit) do
    Enum.take(scored_topics, limit)
  end
end

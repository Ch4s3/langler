defmodule Langler.Content.ClassifierTrainer do
  @moduledoc """
  Helper module for training the ML classifier on existing articles.
  """

  alias Langler.Content.Classifier

  @doc """
  Trains the ML classifier using existing articles with high-confidence topic assignments.
  This uses rule-based classifications as training labels.
  """
  @spec train_from_existing_articles(String.t(), integer()) ::
          {:ok, String.t()} | {:error, term()}
  def train_from_existing_articles(language \\ "spanish", min_articles \\ 50) do
    training_data = Classifier.collect_training_data(0.7, min_articles * 2)

    if length(training_data) < min_articles do
      {:error, :insufficient_data}
    else
      require Logger

      Logger.info(
        "[ClassifierTrainer] Training ML classifier with #{length(training_data)} articles"
      )

      Classifier.train(training_data, language)
    end
  end

  @doc """
  Retrains the classifier periodically as new articles are added.
  Call this from a background job or scheduled task.
  """
  @spec retrain_if_needed(String.t(), integer()) :: :ok | {:error, term()}
  def retrain_if_needed(language \\ "spanish", min_new_articles \\ 100) do
    # Check if we have enough new training data
    training_data = Classifier.collect_training_data(0.7, min_new_articles * 2)

    if length(training_data) >= min_new_articles do
      require Logger

      Logger.info(
        "[ClassifierTrainer] Retraining ML classifier with #{length(training_data)} articles"
      )

      case Classifier.train(training_data, language) do
        {:ok, _model} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end

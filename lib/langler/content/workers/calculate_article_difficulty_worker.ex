defmodule Langler.Content.Workers.CalculateArticleDifficultyWorker do
  @moduledoc """
  Oban worker for calculating article difficulty scores.
  Processes both regular articles and discovered articles.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Langler.Content
  alias Langler.Content.RecommendationScorer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"article_id" => article_id}}) do
    try do
      _article = Content.get_article!(article_id)

      case Content.calculate_article_difficulty(article_id) do
        {:ok, _} ->
          Logger.info("Calculated difficulty for article #{article_id}")
          :ok

        {:error, reason} ->
          Logger.error(
            "Failed to calculate difficulty for article #{article_id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Article #{article_id} not found")
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"discovered_article_id" => discovered_article_id}}) do
    case Content.get_discovered_article(discovered_article_id) do
      nil ->
        Logger.warning("Discovered article #{discovered_article_id} not found")
        :ok

      discovered_article ->
        difficulty_score =
          RecommendationScorer.calculate_discovered_article_difficulty(discovered_article)

        # Calculate avg sentence length from title + summary
        text =
          [discovered_article.title, discovered_article.summary]
          |> Enum.filter(&(&1 && &1 != ""))
          |> Enum.join(" ")

        avg_sentence_length =
          if text != "" do
            sentences =
              text
              |> String.split(~r/[.!?]+/)
              |> Enum.filter(&(&1 != "" && String.trim(&1) != ""))

            words =
              text
              |> String.downcase()
              |> String.split(~r/\W+/u)
              |> Enum.filter(&(&1 != ""))

            if Enum.empty?(sentences) do
              nil
            else
              length(words) / max(length(sentences), 1)
            end
          else
            nil
          end

        case Content.update_discovered_article(discovered_article, %{
               difficulty_score: difficulty_score,
               avg_sentence_length: avg_sentence_length
             }) do
          {:ok, _} ->
            Logger.info("Calculated difficulty for discovered article #{discovered_article_id}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to update discovered article #{discovered_article_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  def perform(%Oban.Job{args: _}) do
    Logger.warning("Invalid job args for CalculateArticleDifficultyWorker")
    :ok
  end
end

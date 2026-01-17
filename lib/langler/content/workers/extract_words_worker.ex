defmodule Langler.Content.Workers.ExtractWordsWorker do
  @moduledoc """
  Oban worker for extracting words from articles.
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"article_id" => _article_id}}) do
    # Placeholder: actual extraction logic will tokenize sentences and persist occurrences.
    :ok
  end
end

defmodule Langler.Content.Workers.CalculateArticleDifficultyWorkerTest do
  use Langler.DataCase, async: true

  alias Langler.Content
  alias Langler.Content.Workers.CalculateArticleDifficultyWorker

  test "returns ok for invalid job args" do
    assert :ok = CalculateArticleDifficultyWorker.perform(%Oban.Job{args: %{"bad" => "args"}})
  end

  test "returns ok when article is missing" do
    assert :ok = CalculateArticleDifficultyWorker.perform(%Oban.Job{args: %{"article_id" => -1}})
  end

  test "updates discovered article difficulty details" do
    {:ok, site} =
      Content.create_source_site(%{
        name: "Example",
        url: "https://example.test",
        discovery_method: "rss",
        language: "spanish"
      })

    Content.upsert_discovered_articles(site.id, [
      %{
        url: "https://example.test/article-1",
        title: "Hola",
        summary: "Mundo"
      }
    ])

    discovered = Content.get_discovered_article_by_url("https://example.test/article-1")

    assert :ok =
             CalculateArticleDifficultyWorker.perform(%Oban.Job{
               args: %{"discovered_article_id" => discovered.id}
             })

    refreshed = Content.get_discovered_article!(discovered.id)

    assert is_number(refreshed.difficulty_score)
    assert is_number(refreshed.avg_sentence_length)
  end
end

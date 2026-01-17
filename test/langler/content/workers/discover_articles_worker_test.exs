defmodule Langler.Content.Workers.DiscoverArticlesWorkerTest do
  use Langler.DataCase, async: true

  alias Langler.Content
  alias Langler.Content.Workers.DiscoverArticlesWorker

  test "returns ok when enqueuing with no eligible sources" do
    assert :ok = DiscoverArticlesWorker.perform(%Oban.Job{args: %{"enqueue_all" => true}})
  end

  test "returns ok when source site is missing" do
    assert :ok = DiscoverArticlesWorker.perform(%Oban.Job{args: %{"source_site_id" => -1}})
  end

  test "skips inactive source sites" do
    {:ok, site} =
      Content.create_source_site(%{
        name: "Inactive",
        url: "https://inactive.test",
        discovery_method: "rss",
        language: "spanish",
        is_active: false
      })

    assert :ok = DiscoverArticlesWorker.perform(%Oban.Job{args: %{"source_site_id" => site.id}})
  end
end

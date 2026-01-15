defmodule Langler.Content.Workers.DiscoverArticlesWorker do
  @moduledoc """
  Oban worker for discovering articles from source sites.
  Processes eligible sources concurrently using Task.async_stream.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias Langler.Content
  alias Langler.Content.Discovery.Discoverer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"enqueue_all" => true}}) do
    enqueue_all_eligible()
  end

  def perform(%Oban.Job{args: %{"source_site_id" => source_site_id}}) do
    case Content.get_source_site(source_site_id) do
      nil ->
        Logger.warning("Source site #{source_site_id} not found")
        :ok

      source_site ->
        if source_site.is_active do
          case Discoverer.discover(source_site) do
            {:ok, count} ->
              Logger.info("Discovered #{count} articles from #{source_site.name}")
              :ok

            {:error, reason} ->
              Logger.error("Discovery failed for #{source_site.name}: #{inspect(reason)}")
              {:error, reason}
          end
        else
          Logger.info("Skipping inactive source site #{source_site.name}")
          :ok
        end
    end
  end

  @doc """
  Enqueues discovery for all eligible source sites.
  Called by cron job or manually.
  """
  @spec enqueue_all_eligible() :: :ok
  def enqueue_all_eligible do
    now = DateTime.utc_now()

    eligible_sources =
      Content.list_active_source_sites()
      |> Enum.filter(fn source ->
        case source.last_checked_at do
          nil ->
            true

          last_checked ->
            hours_since_check = DateTime.diff(now, last_checked, :hour)
            hours_since_check >= source.check_interval_hours
        end
      end)

    Logger.info("Enqueuing discovery for #{length(eligible_sources)} source sites")

    eligible_sources
    |> Task.async_stream(
      fn source ->
        %{"source_site_id" => source.id}
        |> new(unique: [period: 300, keys: [:source_site_id]])
        |> Oban.insert()
      end,
      timeout: :infinity,
      max_concurrency: 5
    )
    |> Stream.run()

    :ok
  end
end

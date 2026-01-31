defmodule Mix.Tasks.Langler.ExtractIdiomsAll do
  @moduledoc """
  Enqueues idiom detection (ExtractIdiomsWorker) for every article in the DB.

  For each article that has at least one sentence, finds a user who has that
  article and has idiom detection enabled (auto_detect_idioms) plus an LLM
  config, then enqueues one job. Articles with no qualifying user are skipped.
  """
  use Mix.Task
  @shortdoc "Enqueue idiom detection for all articles (one job per article)"
  @requirements ["app.config"]

  alias Langler.Accounts
  alias Langler.Accounts.LlmConfig
  alias Langler.Content.Article
  alias Langler.Content.ArticleUser
  alias Langler.Content.Sentence
  alias Langler.Content.Workers.ExtractIdiomsWorker
  alias Langler.Repo
  alias Oban

  import Ecto.Query

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {enqueued, skipped_no_user, skipped_no_sentences} = run_for_all_articles()

    Mix.shell().info("""
    Idiom extraction enqueued:
      Enqueued: #{enqueued}
      Skipped (no qualifying user): #{skipped_no_user}
      Skipped (no sentences): #{skipped_no_sentences}
    """)
  end

  defp run_for_all_articles do
    # All article IDs that have at least one sentence
    article_ids_with_sentences =
      Article
      |> join(:inner, [a], s in Sentence, on: s.article_id == a.id)
      |> distinct([a], a.id)
      |> select([a], a.id)
      |> Repo.all()

    # All (article_id, user_id) from article_users
    article_user_pairs =
      ArticleUser
      |> where([au], au.article_id in ^article_ids_with_sentences)
      |> select([au], {au.article_id, au.user_id})
      |> Repo.all()
      |> Enum.uniq()

    # Group by article_id and pick first user_id per article that has idiom detection + LLM
    article_to_user =
      Enum.reduce(article_user_pairs, %{}, fn {article_id, user_id}, acc ->
        case Map.get(acc, article_id) do
          nil ->
            if user_qualifies?(user_id), do: Map.put(acc, article_id, user_id), else: acc
          _ ->
            acc
        end
      end)

    skipped_no_sentences =
      Repo.aggregate(from(a in Article), :count, :id) - length(article_ids_with_sentences)

    {enqueued, skipped_no_user} =
      article_ids_with_sentences
      |> Enum.reduce({0, 0}, fn article_id, {enc, skip_user} ->
        case Map.get(article_to_user, article_id) do
          nil ->
            {enc, skip_user + 1}

          user_id ->
            %{article_id: article_id, user_id: user_id}
            |> ExtractIdiomsWorker.new()
            |> Oban.insert()

            {enc + 1, skip_user}
        end
      end)

    {enqueued, skipped_no_user, skipped_no_sentences}
  end

  defp user_qualifies?(user_id) do
    pref = Accounts.get_user_preference(user_id)
    pref && pref.auto_detect_idioms && LlmConfig.get_default_config(user_id) != nil
  end
end

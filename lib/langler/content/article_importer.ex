defmodule Langler.Content.ArticleImporter do
  @moduledoc """
  Fetches remote articles, extracts readable content, and seeds sentences + background jobs.
  """

  alias Langler.Accounts
  alias Langler.Content
  alias Langler.Content.Readability
  alias Langler.Content.Workers.ExtractWordsWorker
  alias Langler.Repo
  alias Oban

  require Logger

  @type import_result :: {:ok, Content.Article.t(), :new | :existing} | {:error, term()}

  @spec import_from_url(Accounts.User.t(), String.t()) :: import_result
  def import_from_url(%Accounts.User{} = user, url) when is_binary(url) do
    with {:ok, normalized_url} <- normalize_url(url) do
      case Content.get_article_by_url(normalized_url) do
        %Content.Article{} = article ->
          {:ok, ensure_association(article, user), :existing}

        nil ->
          with {:ok, html} <- fetch_html(normalized_url),
               {:ok, parsed} <- Readability.parse(html, base_url: normalized_url),
               {:ok, article} <- persist_article(user, normalized_url, parsed) do
            enqueue_word_extraction(article)
            {:ok, article, :new}
          else
            {:error, _} = error -> error
          end
      end
    end
  end

  def import_from_url(_, _), do: {:error, :invalid_user}

  defp normalize_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme} = uri} when scheme in ["http", "https"] ->
        {:ok, URI.to_string(uri)}

      {:ok, _} ->
        {:error, :invalid_scheme}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_html(url) do
    req =
      Req.new(
        url: url,
        method: :get,
        redirect: :follow,
        headers: [{"user-agent", "LanglerBot/0.1"}],
        receive_timeout: 10_000
      )

    case Req.get(req) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_article(user, url, parsed) do
    Repo.transaction(fn ->
      with {:ok, article} <- create_article(parsed, url, user),
           {:ok, _} <- Content.ensure_article_user(article, user.id),
           :ok <- seed_sentences(article, parsed[:content] || parsed["content"]) do
        article
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_article(parsed, url, user) do
    language = user_language(user)
    source = URI.parse(url).host

    Content.create_article(%{
      title: parsed[:title] || parsed["title"] || url,
      url: url,
      source: source,
      language: language,
      content: sanitize_content(parsed[:content] || parsed["content"] || ""),
      extracted_at: DateTime.utc_now()
    })
  end

  defp user_language(user) do
    case Accounts.get_user_preference(user.id) do
      nil -> "spanish"
      pref -> pref.target_language
    end
  end

  defp seed_sentences(article, content) when is_binary(content) do
    content
    |> sanitize_content()
    |> split_sentences()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {sentence, idx}, _ ->
      case Content.create_sentence(%{
             article_id: article.id,
             content: sentence,
             position: idx
           }) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp sanitize_content(nil), do: ""

  defp sanitize_content(content) do
    content
    |> String.replace(~r/<head[\s\S]*?<\/head>/im, "")
    |> String.replace(~r/<(script|style)[\s\S]*?>[\s\S]*?<\/\1>/im, "")
    |> strip_tags()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_tags(content) do
    Regex.replace(~r/<[^>]*>/, content, "")
  end

  defp split_sentences(content) do
    content
    |> String.trim()
    |> String.split(~r/(?<=[\.!\?])\s+/, trim: true)
  end

  defp ensure_association(article, user) do
    {:ok, _} = Content.ensure_article_user(article, user.id)
    article
  end

  defp enqueue_word_extraction(article) do
    %{article_id: article.id}
    |> ExtractWordsWorker.new()
    |> Oban.insert()
  end
end

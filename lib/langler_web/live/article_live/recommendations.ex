defmodule LanglerWeb.ArticleLive.Recommendations do
  @moduledoc """
  LiveView for article recommendations.
  """

  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.{ArticleImporter, Classifier, Topics}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    user_id = user.id

    {:ok,
     socket
     |> assign(:importing, false)
     |> assign_async(:recommended_articles, fn ->
       {:ok, %{recommended_articles: Content.get_recommended_articles(user_id, 10)}}
     end)
     |> assign(:form, to_form(%{"url" => ""}, as: :article))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-shell space-y-8">
        <div class="section-card p-8">
          <div class="section-header">
            <p class="section-header__eyebrow">Discover</p>
            <h1 class="section-header__title">Suggested for you</h1>
            <p class="section-header__lede">
              Articles recommended based on your reading preferences.
            </p>
          </div>

          <.async_result :let={recommended_articles} assign={@recommended_articles}>
            <:loading>
              <div class="mt-6 rounded-2xl border border-dashed border-base-200 bg-base-50/80 p-6 text-base-content/70">
                <div class="flex items-center gap-2">
                  <span class="loading loading-spinner loading-sm"></span>
                  <span>Loading recommendations...</span>
                </div>
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="mt-6 rounded-2xl border border-dashed border-base-200 bg-base-50/80 p-6 text-base-content/70">
                Unable to load recommendations.
              </div>
            </:failed>
            <div
              :if={length(recommended_articles) == 0}
              class="mt-6 rounded-2xl border border-dashed border-base-200 bg-base-50/80 p-6 text-base-content/70"
            >
              No recommendations available yet. Import some articles to get personalized suggestions.
            </div>

            <.card_grid :if={length(recommended_articles) > 0}>
              <.card
                :for={article <- recommended_articles}
                variant={:default}
                hover
                class="section-card bg-base-100/90"
              >
                <:header>
                  <div class="space-y-2">
                    <p class="card-title text-lg font-semibold text-base-content">
                      {article.title || article.url}
                    </p>
                    <p class="text-xs uppercase tracking-[0.2em] text-base-content/50">
                      {article.source || URI.parse(article.url).host}
                    </p>
                    <div class="flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/70">
                      <span class="badge badge-sm badge-primary badge-outline uppercase tracking-wide">
                        {article.language}
                      </span>
                      <span
                        :if={article.is_discovered}
                        class="badge badge-sm badge-info/80 text-base-content/50"
                      >
                        New
                      </span>
                      <span
                        :for={topic <- top_topics(article)}
                        :if={top_topics(article) != []}
                        class="badge badge-sm badge-ghost"
                      >
                        {Topics.topic_name(article.language, topic.topic)}
                      </span>
                    </div>
                    <% difficulty = difficulty_info(article) %>
                    <div class="flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/60">
                      <span class="uppercase tracking-[0.2em] text-base-content/70">Difficulty</span>
                      <div
                        class="flex items-center gap-1"
                        aria-label={"Difficulty #{difficulty.rating} of 4"}
                      >
                        <span
                          :for={index <- 1..4}
                          class={[
                            "h-2 w-2 rounded-full",
                            index <= difficulty.rating && "bg-primary",
                            index > difficulty.rating && "bg-base-300"
                          ]}
                        >
                        </span>
                      </div>
                    </div>
                  </div>
                </:header>

                <p
                  :if={article.content && article.content != ""}
                  class="line-clamp-3 text-sm text-base-content/70"
                >
                  {article.content |> String.slice(0, 220)}
                  {if String.length(article.content || "") > 220, do: "…"}
                </p>

                <:actions>
                  <div class="flex flex-wrap items-center justify-between gap-3 w-full text-sm">
                    <span class="text-xs text-base-content/60">
                      {if article.published_at do
                        "Published #{format_timestamp(article.published_at)}"
                      else
                        "Discovered #{format_timestamp(article.inserted_at)}"
                      end}
                    </span>
                    <button
                      type="button"
                      class="btn btn-sm btn-primary"
                      phx-click="import_recommended"
                      phx-value-url={article.url}
                      phx-disable-with="Importing..."
                      disabled={@importing}
                    >
                      <.icon name="hero-arrow-down-on-square" class="h-4 w-4" /> Import
                    </button>
                  </div>
                </:actions>
              </.card>
            </.card_grid>
          </.async_result>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("import_recommended", %{"url" => url}, socket) do
    user = socket.assigns.current_scope.user
    user_id = user.id
    socket = assign(socket, importing: true)

    case ArticleImporter.import_from_url(user, url) do
      {:ok, article, _status} ->
        # Mark discovered article as imported if it exists
        if discovered_article = Content.get_discovered_article_by_url(url) do
          Content.mark_discovered_article_imported(discovered_article.id, user.id)
        end

        {:noreply,
         socket
         |> put_flash(:info, gettext("Imported %{title}", title: article.title))
         |> assign(:importing, false)
         |> assign_async(:recommended_articles, fn ->
           articles = Content.get_recommended_articles(user_id, 10)
           {:ok, %{recommended_articles: articles}}
         end)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Import failed: %{details}", details: humanize_error(reason))
         )
         |> assign(:importing, false)}
    end
  end

  defp humanize_error(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp humanize_error(reason) when is_atom(reason), do: Phoenix.Naming.humanize(reason)
  defp humanize_error(reason) when is_tuple(reason), do: inspect(reason)
  defp humanize_error(%{__struct__: _} = struct), do: inspect(struct)
  defp humanize_error(reason), do: to_string(reason)

  defp difficulty_info(article) do
    base_score = Map.get(article, :difficulty_score)
    sentence_length = article_sentence_length(article)

    adjusted_score =
      case base_score do
        nil -> estimate_score_from_sentence_length(sentence_length) || 5.0
        score -> score + sentence_length_adjustment(sentence_length)
      end

    adjusted_score = clamp(adjusted_score, 0.0, 10.0)

    %{
      rating: score_to_rating(adjusted_score),
      cefr: cefr_from_score(adjusted_score),
      sentence_length: sentence_length
    }
  end

  defp article_sentence_length(article) do
    Map.get(article, :avg_sentence_length) ||
      estimate_sentence_length(Map.get(article, :content))
  end

  defp estimate_sentence_length(content) when is_binary(content) do
    trimmed = String.trim(content)

    if trimmed == "" do
      nil
    else
      lengths =
        trimmed
        |> String.split(~r/[.!?]+/, trim: true)
        |> Enum.map(&word_count/1)
        |> Enum.filter(&(&1 > 0))

      if lengths == [] do
        nil
      else
        Enum.sum(lengths) / length(lengths)
      end
    end
  end

  defp estimate_sentence_length(_), do: nil

  defp word_count(sentence) do
    sentence
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp estimate_score_from_sentence_length(nil), do: nil

  defp estimate_score_from_sentence_length(length) do
    cond do
      length < 10 -> 2.0
      length < 15 -> 3.5
      length < 20 -> 5.0
      length < 25 -> 7.0
      true -> 8.5
    end
  end

  defp sentence_length_adjustment(nil), do: 0.0
  defp sentence_length_adjustment(length) when length < 12, do: -0.4
  defp sentence_length_adjustment(length) when length < 18, do: 0.0
  defp sentence_length_adjustment(length) when length < 24, do: 0.4
  defp sentence_length_adjustment(_length), do: 0.8

  defp score_to_rating(score) do
    cond do
      score < 2.5 -> 1
      score < 4.5 -> 2
      score < 7.0 -> 3
      true -> 4
    end
  end

  defp cefr_from_score(score) do
    cond do
      score < 2.0 -> "A1"
      score < 4.0 -> "A2"
      score < 6.0 -> "B1"
      score < 8.0 -> "B2"
      score < 9.0 -> "C1"
      true -> "C2"
    end
  end

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp top_topics(%{article_topics: topics}) when is_list(topics) and topics != [] do
    topics
    |> Enum.sort_by(fn topic -> topic_confidence(topic) end, :desc)
    |> Enum.take(3)
  end

  # For articles without topics (regular or discovered), classify them
  defp top_topics(article) do
    title = Map.get(article, :title, "")
    content = Map.get(article, :content, "") || Map.get(article, :summary, "")
    language = Map.get(article, :language, "spanish") || "spanish"

    content_text = [title, content] |> Enum.filter(&(&1 && &1 != "")) |> Enum.join(" ")

    if String.trim(content_text) != "" do
      Classifier.classify(content_text, language)
      |> Enum.map(fn {topic, confidence} ->
        %{topic: topic, confidence: confidence}
      end)
      |> Enum.sort_by(&topic_confidence/1, :desc)
      |> Enum.take(3)
    else
      []
    end
  end

  defp topic_confidence(%{confidence: %Decimal{} = confidence}), do: Decimal.to_float(confidence)
  defp topic_confidence(%{confidence: confidence}) when is_number(confidence), do: confidence
  defp topic_confidence(_), do: 0.0
end

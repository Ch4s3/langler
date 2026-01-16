defmodule LanglerWeb.ArticleLive.Recommendations do
  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.Content.Topics

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    current_user = scope.user
    recommended_articles = Content.get_recommended_articles(current_user.id, 10)

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:importing, false)
     |> assign(:recommended_articles, recommended_articles)
     |> assign(:form, to_form(%{"url" => ""}, as: :article))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl space-y-8 px-4 py-8 sm:px-6 lg:px-0">
        <div>
          <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
            Discover
          </p>
          <h1 class="text-3xl font-semibold text-base-content">Suggested for you</h1>
          <p class="mt-2 text-sm text-base-content/70">
            Articles recommended based on your reading preferences.
          </p>
        </div>

        <div
          :if={length(@recommended_articles) == 0}
          class="card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur"
        >
          <div class="card-body">
            <div class="alert border border-dashed border-base-300 text-base-content/70">
              No recommendations available yet. Import some articles to get personalized suggestions.
            </div>
          </div>
        </div>

        <div :if={length(@recommended_articles) > 0} class="grid gap-4 md:grid-cols-2">
          <div :for={article <- @recommended_articles} class="relative group">
            <div class="card border border-base-200 bg-base-100/80 shadow hover:shadow-xl transition">
              <div class="card-body gap-5">
                <div class="space-y-2">
                  <p class="text-lg font-semibold text-base-content">
                    {article.title || article.url}
                  </p>
                  <p class="text-xs uppercase tracking-[0.2em] text-base-content/50">
                    {article.source || URI.parse(article.url).host}
                  </p>
                  <div class="flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/70">
                    <span class="badge badge-sm badge-primary badge-outline uppercase tracking-wide">
                      {article.language}
                    </span>
                    <span :if={article.is_discovered} class="badge badge-sm badge-info/80 text-white">
                      New
                    </span>
                    <span
                      :for={topic <- Content.list_topics_for_article(article.id) |> Enum.take(3)}
                      :if={article.id}
                      class="badge badge-sm badge-ghost"
                    >
                      {Topics.topic_name(article.language, topic.topic)}
                    </span>
                  </div>
                  <% difficulty = difficulty_info(article) %>
                  <div class="flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/60">
                    <span class="uppercase tracking-[0.2em] text-base-content/40">Difficulty</span>
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
                    <span class="badge badge-sm badge-ghost">{difficulty.cefr}</span>
                    <span class="text-[0.65rem] uppercase tracking-[0.2em] text-base-content/40">
                      {difficulty.rating}/4
                    </span>
                  </div>
                </div>
                <p
                  :if={article.content && article.content != ""}
                  class="line-clamp-3 text-sm text-base-content/70"
                >
                  {article.content |> String.slice(0, 220)}
                  {if String.length(article.content || "") > 220, do: "…"}
                </p>
                <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
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
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("import_recommended", %{"url" => url}, socket) do
    user = socket.assigns.current_user
    socket = assign(socket, importing: true)

    case ArticleImporter.import_from_url(user, url) do
      {:ok, article, _status} ->
        # Mark discovered article as imported if it exists
        if discovered_article = Content.get_discovered_article_by_url(url) do
          Content.mark_discovered_article_imported(discovered_article.id, user.id)
        end

        # Remove from recommendations and refresh list
        recommended_articles =
          socket.assigns.recommended_articles
          |> Enum.reject(&(&1.url == url))

        {:noreply,
         socket
         |> put_flash(:info, "Imported #{article.title}")
         |> assign(importing: false, recommended_articles: recommended_articles)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, humanize_error(reason))
         |> assign(importing: false)}
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
end

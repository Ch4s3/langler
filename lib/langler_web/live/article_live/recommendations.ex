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

        <div :if={length(@recommended_articles) == 0} class="card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body">
            <div class="alert border border-dashed border-base-300 text-base-content/70">
              No recommendations available yet. Import some articles to get personalized suggestions.
            </div>
          </div>
        </div>

        <div :if={length(@recommended_articles) > 0} class="grid gap-4 md:grid-cols-2">
          <div :for={article <- @recommended_articles} class="relative group">
            <div class="card border border-base-200 bg-base-100/80 shadow hover:shadow-xl transition">
              <div class="card-body gap-4">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div class="flex-1">
                    <p class="text-lg font-semibold text-base-content">
                      {article.title || article.url}
                    </p>
                    <p class="text-xs uppercase tracking-wide text-base-content/50">
                      {article.source || URI.parse(article.url).host}
                    </p>
                  </div>
                  <div class="flex flex-col items-end gap-2">
                    <span class="badge badge-primary badge-outline uppercase tracking-wide">
                      {article.language}
                    </span>
                    <div class="flex flex-wrap gap-1 justify-end">
                      <span
                        :if={article.id}
                        :for={topic <- Content.list_topics_for_article(article.id) |> Enum.take(3)}
                        class="badge badge-xs badge-ghost"
                      >
                        {Topics.topic_name(article.language, topic.topic)}
                      </span>
                      <span :if={article.is_discovered} class="badge badge-xs badge-info">
                        New
                      </span>
                    </div>
                  </div>
                </div>
                <p :if={article.content && article.content != ""} class="line-clamp-3 text-sm text-base-content/70">
                  {article.content |> String.slice(0, 220)}
                  {if String.length(article.content || "") > 220, do: "…"}
                </p>
                <div class="flex items-center justify-between">
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
  defp humanize_error(reason), do: to_string(reason)

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end

defmodule LanglerWeb.ArticleLive.Index do
  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.ArticleImporter

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    current_user = scope.user
    articles = Content.list_articles_for_user(current_user.id)

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:importing, false)
     |> assign(:articles_count, length(articles))
     |> assign(:form, to_form(%{"url" => ""}, as: :article))
     |> stream(:articles, articles)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl space-y-8 py-8">
        <div class="card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body space-y-4">
            <div>
              <h1 class="text-3xl font-semibold text-base-content">Import an article</h1>
              <p class="mt-2 text-sm text-base-content/70">
                Paste a URL to extract the readable content and queue vocabulary analysis.
              </p>
            </div>

            <.form
              for={@form}
              id="article-import-form"
              class="space-y-4"
              phx-submit="import"
              phx-change="validate"
            >
              <.input
                field={@form[:url]}
                type="url"
                label="Article URL"
                placeholder="https://elpais.com/cultura/..."
                required
                disabled={@importing}
              />
              <div class="flex justify-end">
                <.button
                  phx-disable-with="Importing..."
                  disabled={@importing}
                  class="btn btn-primary gap-2"
                >
                  <.icon name="hero-arrow-down-on-square" class="h-4 w-4" /> Import Article
                </.button>
              </div>
            </.form>
          </div>
        </div>

        <div class="card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body space-y-6">
            <div class="flex items-center justify-between gap-4">
              <div>
                <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                  Library
                </p>
                <h2 class="text-2xl font-semibold text-base-content">Your articles</h2>
              </div>
              <span class="badge badge-lg badge-outline font-semibold text-base-content/80">
                {@articles_count}
              </span>
            </div>

            <div
              id="articles"
              phx-update="stream"
              class="grid gap-4"
            >
              <div class={[
                "alert border border-dashed border-base-300 text-base-content/70",
                @articles_count > 0 && "hidden"
              ]}>
                No articles yet. Import one to get started.
              </div>

              <div :for={{dom_id, article} <- @streams.articles} id={dom_id}>
                <.link
                  navigate={~p"/articles/#{article}"}
                  class="block rounded-xl no-underline transition hover:-translate-y-0.5 hover:shadow-xl focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
                >
                  <div class="card border border-base-200 bg-base-100/80 shadow">
                    <div class="card-body gap-3">
                      <div class="flex flex-wrap items-center justify-between gap-3">
                        <div>
                          <p class="text-lg font-semibold text-base-content">{article.title}</p>
                          <p class="text-xs uppercase tracking-wide text-base-content/50">
                            {article.source || URI.parse(article.url).host}
                          </p>
                        </div>
                        <span class="badge badge-primary badge-outline uppercase tracking-wide">
                          {article.language}
                        </span>
                      </div>
                      <p class="line-clamp-2 text-sm text-base-content/70">
                        {article.content |> String.slice(0, 220)}
                        {if String.length(article.content || "") > 220, do: "…"}
                      </p>
                    </div>
                  </div>
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("validate", %{"article" => params}, socket) do
    changeset = %{"url" => Map.get(params, "url", "")}
    {:noreply, assign(socket, form: to_form(changeset, as: :article))}
  end

  def handle_event("import", %{"article" => %{"url" => url}}, socket) do
    user = socket.assigns.current_user

    socket = assign(socket, importing: true)

    case ArticleImporter.import_from_url(user, url) do
      {:ok, article, status} ->
        count_delta = if status == :new, do: 1, else: 0

        {:noreply,
         socket
         |> put_flash(:info, "Imported #{article.title}")
         |> assign(
           importing: false,
           form: to_form(%{"url" => ""}, as: :article),
           articles_count: socket.assigns.articles_count + count_delta
         )
         |> stream_insert(:articles, article, at: 0)}

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
end

defmodule LanglerWeb.ArticleLive.Index do
  use LanglerWeb, :live_view

  alias Langler.Accounts
  alias Langler.Content
  alias Langler.Content.ArticleImporter

  def mount(_params, _session, socket) do
    current_user = ensure_user()

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:importing, false)
     |> assign(:form, to_form(%{"url" => ""}, as: :article))
     |> stream(:articles, Content.list_articles())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-4xl space-y-8 py-8">
        <div class="rounded-2xl border border-slate-200 bg-white/80 p-6 shadow-sm backdrop-blur">
          <h1 class="text-2xl font-semibold text-slate-900">Import an article</h1>
          <p class="mt-2 text-sm text-slate-500">
            Paste a URL to extract the readable content and queue vocabulary analysis.
          </p>

          <.form
            for={@form}
            id="article-import-form"
            class="mt-6 space-y-4"
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
                class="inline-flex items-center gap-2"
              >
                <.icon name="hero-arrow-down-on-square" class="h-4 w-4" /> Import Article
              </.button>
            </div>
          </.form>
        </div>

        <div class="rounded-2xl border border-slate-200 bg-white/80 p-6 shadow-sm backdrop-blur">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-semibold text-slate-900">Your articles</h2>
            <span class="text-sm text-slate-500">
              {length(@streams.articles)}
            </span>
          </div>

          <div
            id="articles"
            phx-update="stream"
            class="mt-4 divide-y divide-slate-100 rounded-xl border border-slate-100 bg-white shadow-inner"
          >
            <div class={[
              "p-6 text-center text-sm text-slate-400",
              length(@streams.articles) > 0 && "hidden"
            ]}>
              No articles yet. Import one to get started.
            </div>

            <div
              :for={{dom_id, article} <- @streams.articles}
              id={dom_id}
              class="group flex flex-col gap-2 p-6 transition hover:bg-slate-50/70"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="text-base font-medium text-slate-900">{article.title}</p>
                  <p class="text-xs text-slate-500">
                    {article.source || URI.parse(article.url).host}
                  </p>
                </div>
                <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium uppercase tracking-wide text-slate-600">
                  {article.language}
                </span>
              </div>
              <p class="line-clamp-2 text-sm text-slate-500">
                {article.content |> String.slice(0, 220)}
                {if String.length(article.content || "") > 220, do: "…"}
              </p>
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
      {:ok, article} ->
        {:noreply,
         socket
         |> put_flash(:info, "Imported #{article.title}")
         |> assign(importing: false, form: to_form(%{"url" => ""}, as: :article))
         |> stream_insert(:articles, article, at: 0)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, humanize_error(reason))
         |> assign(importing: false)}
    end
  end

  defp ensure_user do
    Accounts.ensure_demo_user()
  end

  defp humanize_error(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp humanize_error(reason) when is_atom(reason), do: Phoenix.Naming.humanize(reason)
  defp humanize_error(reason), do: to_string(reason)
end

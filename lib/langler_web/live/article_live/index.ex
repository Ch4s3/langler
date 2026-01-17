defmodule LanglerWeb.ArticleLive.Index do
  @moduledoc """
  LiveView for listing and importing articles.
  """

  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.Content.FrontPage
  alias Langler.Content.Topics

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    current_user = scope.user
    articles = Content.list_articles_for_user(current_user.id)
    user_topics = Content.get_user_topics(current_user.id)

    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> assign(:importing, false)
     |> assign(:selected_source, nil)
     |> assign(:selected_topic, nil)
     |> assign(:user_topics, user_topics)
     |> assign(:articles_count, length(articles))
     |> assign(:form, to_form(%{"url" => ""}, as: :article))
     |> stream(:articles, articles)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-10">
        <div class="surface-panel card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body space-y-6">
            <div>
              <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                Import an article
              </p>
              <h1 class="text-3xl font-semibold text-base-content">Build your reading queue</h1>
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
              <div class="relative">
                <.input
                  field={@form[:url]}
                  type="url"
                  label="Article URL"
                  placeholder="https://elpais.com/cultura/..."
                  required
                  disabled={@importing}
                  phx-debounce="300"
                  class={url_input_classes(@selected_source)}
                />
                <button
                  :if={@selected_source}
                  type="button"
                  class="btn btn-sm absolute right-3 top-10 gap-2 rounded-full border border-base-300 bg-base-100/90 px-4 text-sm font-semibold text-base-content shadow transition hover:-translate-y-0.5 hover:shadow-lg focus-visible:ring focus-visible:ring-primary/40"
                  phx-click="random_from_source"
                  phx-value-source={@selected_source.id}
                  phx-disable-with="Searching..."
                  disabled={@importing}
                >
                  <.icon name="hero-sparkles" class="h-4 w-4" /> Random from {@selected_source.label}
                </button>
              </div>
              <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/70">
                <p>Need inspiration?</p>
                <div class="chip-group">
                  <button
                    :for={sample <- sample_links()}
                    type="button"
                    class="chip"
                    phx-click="prefill_url"
                    phx-value-url={sample.url}
                    phx-value-source={sample.id}
                    disabled={@importing}
                  >
                    {sample.label}
                  </button>
                </div>
              </div>
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

        <div class="surface-panel card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body space-y-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                  Library
                </p>
                <h2 class="text-2xl font-semibold text-base-content">Your articles</h2>
              </div>
              <div class="flex flex-col items-end gap-2 sm:flex-row sm:items-center sm:gap-4">
                <.link
                  navigate={~p"/articles/recommendations"}
                  class="link text-sm font-semibold text-primary"
                >
                  See recommendations →
                </.link>
                <span class="badge badge-lg badge-outline font-semibold text-base-content/80 self-start">
                  {@articles_count}
                </span>
              </div>
            </div>

            <div :if={length(@user_topics) > 0} class="flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="filter_topic"
                phx-value-topic=""
                class={[
                  "badge badge-lg transition",
                  if(@selected_topic == nil, do: "badge-primary", else: "badge-outline")
                ]}
              >
                Todos
              </button>
              <button
                :for={topic <- @user_topics}
                type="button"
                phx-click="filter_topic"
                phx-value-topic={topic}
                class={[
                  "badge badge-lg transition",
                  if(@selected_topic == topic, do: "badge-primary", else: "badge-outline")
                ]}
              >
                {get_topic_name(@current_user, topic)}
              </button>
            </div>

            <div
              id="articles"
              phx-update="stream"
              class="grid gap-4 md:grid-cols-2"
            >
              <div
                id="articles-empty-state"
                class={[
                  "alert border border-dashed border-base-300 text-base-content/70",
                  @articles_count > 0 && "hidden"
                ]}
              >
                No articles yet. Import one to get started.
              </div>

              <div :for={{dom_id, article} <- @streams.articles} id={dom_id} class="relative group">
                <.link
                  navigate={~p"/articles/#{article}"}
                  class="block rounded-2xl no-underline transition hover:-translate-y-1 hover:shadow-2xl focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/60"
                >
                  <div class="surface-panel card border border-base-200 bg-base-100/80 shadow">
                    <div class="card-body gap-4">
                      <div class="space-y-3">
                        <p class="text-xl font-semibold leading-snug text-base-content">
                          {article.title}
                        </p>
                        <div class="flex flex-wrap items-center justify-between gap-3 text-xs uppercase tracking-wide text-base-content/60">
                          <span class="font-semibold">
                            {article.source || URI.parse(article.url).host}
                          </span>
                          <div class="flex flex-wrap items-center gap-2">
                            <span class="badge badge-primary badge-outline uppercase tracking-wide">
                              {article.language}
                            </span>
                            <div class="flex flex-wrap gap-1">
                              <span
                                :for={
                                  topic <- Content.list_topics_for_article(article.id) |> Enum.take(3)
                                }
                                class="badge badge-xs badge-ghost normal-case"
                              >
                                {Topics.topic_name(article.language, topic.topic)}
                              </span>
                            </div>
                          </div>
                        </div>
                      </div>
                      <p class="line-clamp-3 text-sm text-base-content/70">
                        {article.content |> String.slice(0, 220)}
                        {if String.length(article.content || "") > 220, do: "…"}
                      </p>
                      <div class="flex items-center justify-between text-xs text-base-content/60">
                        <span>Imported {format_timestamp(article.inserted_at)}</span>
                        <span class="inline-flex items-center gap-1 font-semibold text-primary">
                          Continue <.icon name="hero-arrow-right" class="h-3 w-3" />
                        </span>
                      </div>
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
    url = Map.get(params, "url", "")
    source = find_source_for_url(url)
    changeset = %{"url" => url}

    {:noreply,
     socket
     |> assign(:selected_source, source)
     |> assign(:form, to_form(changeset, as: :article))}
  end

  def handle_event("import", %{"article" => %{"url" => url}}, socket) do
    case import_article(socket, url) do
      {:ok, new_socket} -> {:noreply, new_socket}
      {:error, new_socket} -> {:noreply, new_socket}
    end
  end

  def handle_event("prefill_url", %{"url" => url} = params, socket) do
    source = find_source_from_params(params)

    {:noreply,
     socket
     |> assign(:selected_source, source)
     |> assign(:form, to_form(%{"url" => url}, as: :article))}
  end

  def handle_event("random_from_source", %{"source" => source_id}, socket) do
    case find_source_by_id(source_id) do
      nil -> {:noreply, put_flash(socket, :error, "Unknown source")}
      source -> handle_random_article_import(socket, source)
    end
  end

  def handle_event("filter_topic", %{"topic" => ""}, socket) do
    user_id = socket.assigns.current_user.id
    articles = Content.list_articles_for_user(user_id)

    {:noreply,
     socket
     |> assign(:selected_topic, nil)
     |> assign(:articles_count, length(articles))
     |> stream(:articles, articles, reset: true)}
  end

  def handle_event("filter_topic", %{"topic" => topic}, socket) do
    user_id = socket.assigns.current_user.id
    articles = Content.get_articles_by_topic(topic, user_id)

    {:noreply,
     socket
     |> assign(:selected_topic, topic)
     |> assign(:articles_count, length(articles))
     |> stream(:articles, articles, reset: true)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <- Content.delete_article_for_user(socket.assigns.current_user.id, article_id) do
      {:noreply,
       socket
       |> update(:articles_count, &max(&1 - 1, 0))
       |> stream_delete(:articles, %{id: article_id})
       |> put_flash(:info, "Article removed")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Article not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to delete: #{inspect(reason)}")}
    end
  end

  defp handle_random_article_import(socket, source) do
    socket = assign(socket, importing: true, selected_source: source)

    case FrontPage.random_article(source) do
      {:ok, url} -> import_random_article(socket, source, url)
      {:error, reason} -> handle_random_article_error(socket, source, reason)
    end
  end

  defp import_random_article(socket, source, url) do
    flash = "Imported a #{source.label} article from the front page."

    case import_article(socket, url, flash: flash) do
      {:ok, new_socket} -> {:noreply, new_socket}
      {:error, new_socket} -> {:noreply, new_socket}
    end
  end

  defp handle_random_article_error(socket, source, reason) do
    {:noreply,
     socket
     |> assign(:importing, false)
     |> put_flash(:error, random_error_message(source, reason))}
  end

  defp humanize_error(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp humanize_error(reason) when is_atom(reason), do: Phoenix.Naming.humanize(reason)

  defp humanize_error(%_{} = reason) do
    if function_exported?(reason.__struct__, :exception, 1) do
      Exception.message(reason)
    else
      inspect(reason)
    end
  end

  defp humanize_error(reason), do: to_string(reason)

  defp sample_links do
    curated_sources()
    |> Enum.map(&%{label: &1.label, url: &1.sample_url, id: &1.id})
  end

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}

  defp get_topic_name(user, topic) do
    language =
      case Langler.Accounts.get_user_preference(user.id) do
        nil -> "spanish"
        pref -> pref.target_language || "spanish"
      end

    Topics.topic_name(language, topic)
  end

  defp import_article(socket, url, opts \\ []) do
    trimmed = String.trim(to_string(url || ""))

    if trimmed == "" do
      {:error, put_flash(socket, :error, "Please provide a URL.")}
    else
      process_article_import(socket, trimmed, opts)
    end
  end

  defp process_article_import(socket, trimmed, opts) do
    user = socket.assigns.current_user
    socket = assign(socket, importing: true)

    case ArticleImporter.import_from_url(user, trimmed) do
      {:ok, article, status} -> handle_successful_import(socket, article, status, trimmed, opts)
      {:error, reason} -> handle_import_error(socket, reason)
    end
  end

  defp handle_successful_import(socket, article, status, trimmed, opts) do
    count_delta = if status == :new, do: 1, else: 0
    form_payload = if opts[:keep_url], do: %{"url" => trimmed}, else: %{"url" => ""}
    flash_message = opts[:flash] || "Imported #{article.title || article.url}"

    {:ok,
     socket
     |> put_flash(:info, flash_message)
     |> assign(
       importing: false,
       form: to_form(form_payload, as: :article),
       articles_count: socket.assigns.articles_count + count_delta
     )
     |> stream_insert(:articles, article, at: 0)}
  end

  defp handle_import_error(socket, reason) do
    {:error,
     socket
     |> put_flash(:error, humanize_error(reason))
     |> assign(importing: false)}
  end

  defp url_input_classes(nil), do: "w-full input"
  defp url_input_classes(_source), do: "w-full input pr-40"

  defp curated_sources do
    [
      %{
        id: "elpais",
        label: "El País",
        sample_url: "https://elpais.com/ciencia",
        front_page: "https://elpais.com",
        hosts: ["elpais.com"],
        article_pattern: ~r{^https?://(?:www\.)?elpais\.com/.+\.html$}
      },
      %{
        id: "bbcmundo",
        label: "BBC Mundo",
        sample_url: "https://www.bbc.com/mundo",
        front_page: "https://www.bbc.com/mundo",
        hosts: ["bbc.com"],
        article_pattern: ~r{^https?://www\.bbc\.com/mundo/articles/.+}
      },
      %{
        id: "elmundo",
        label: "El Mundo",
        sample_url: "https://www.elmundo.es",
        front_page: "https://www.elmundo.es",
        hosts: ["elmundo.es"],
        article_pattern: ~r{^https?://(?:www\.)?elmundo\.es/.+\.html$}
      }
    ]
  end

  defp find_source_from_params(%{"source" => id}) when byte_size(id) > 0 do
    find_source_by_id(id)
  end

  defp find_source_from_params(_), do: nil

  defp find_source_by_id(nil), do: nil

  defp find_source_by_id(id) do
    Enum.find(curated_sources(), &(&1.id == id))
  end

  defp find_source_for_url(url) when is_binary(url) and url != "" do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        Enum.find(curated_sources(), fn source ->
          Enum.any?(source.hosts, &String.ends_with?(host, &1))
        end)

      _ ->
        nil
    end
  end

  defp find_source_for_url(_), do: nil

  defp random_error_message(source, {:http_error, status}) do
    "Unable to reach #{source.label} (status #{status}). Try again in a bit."
  end

  @dialyzer {:nowarn_function, random_error_message: 2}
  defp random_error_message(source, :no_matches) do
    "No article links found on #{source.label}'s front page."
  end

  defp random_error_message(source, :no_links) do
    "No article links found on #{source.label}'s front page."
  end

  defp random_error_message(source, reason) do
    "Something went wrong fetching #{source.label}: #{inspect(reason)}"
  end
end

defmodule LanglerWeb.ArticleLive.Index do
  @moduledoc """
  LiveView for listing and importing articles.
  """

  use LanglerWeb, :live_view

  require Logger

  alias Langler.Content
  alias Langler.Content.ArticleImporter
  alias Langler.Content.FrontPage
  alias Langler.Content.Topics

  @recommendations_limit 10

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    user = scope.user
    user_id = user.id

    # Preload user settings to avoid N+1 queries in template
    target_language = get_target_language(user)
    user_topics = Content.get_user_topics(user_id)

    {:ok,
     socket
     |> assign(:importing, false)
     |> assign(:selected_source, nil)
     |> assign(:selected_topic, nil)
     |> assign(:query, "")
     |> assign(:target_language, target_language)
     |> assign(:user_topics, user_topics)
     |> assign(:articles_count, 0)
     |> assign(:articles_loading, false)
     |> stream(:articles, [])
     |> assign_async(:recommended_count, fn ->
       {:ok, %{recommended_count: Content.get_recommended_count(user_id, @recommendations_limit)}}
     end)
     |> assign(:form, to_form(%{"url" => ""}, as: :article))}
  end

  defp get_target_language(user) do
    case Langler.Accounts.get_user_preference(user.id) do
      nil -> "spanish"
      pref -> pref.target_language || "spanish"
    end
  end

  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "") |> String.trim()

    # Only update if different (idempotent - prevents rerenders)
    socket =
      cond do
        socket.assigns[:query] == query &&
          not socket.assigns.articles_loading &&
            socket.assigns.articles_count > 0 ->
          # Query unchanged and articles already loaded
          socket

        socket.assigns[:query] == query ->
          # Query unchanged but articles not loaded yet
          if socket.assigns.articles_count == 0 do
            load_articles_async(socket)
          else
            socket
          end

        true ->
          # Query changed
          socket
          |> assign(:query, query)
          |> load_articles_async()
      end

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-10">
        <div class="surface-panel card">
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

            <div
              :if={@importing}
              class="alert alert-info border border-base-200 bg-base-100/70 text-base-content/70"
            >
              <span class="loading loading-spinner loading-sm"></span>
              <span class="text-sm font-semibold">Importing…</span>
              <span class="text-sm">This usually takes a few seconds.</span>
            </div>

            <.form
              for={@form}
              id="article-import-form"
              class="space-y-4"
              phx-submit="import"
              phx-change="validate"
            >
              <div class="space-y-3">
                <.input
                  field={@form[:url]}
                  type="url"
                  label="Article URL"
                  placeholder="https://elpais.com/cultura/..."
                  required
                  disabled={@importing}
                  phx-debounce="300"
                  class="w-full input"
                />
                <div :if={@selected_source} class="flex flex-wrap items-center justify-between gap-3">
                  <div class="flex flex-wrap items-center gap-2 text-xs font-semibold text-base-content/60">
                    <span class="badge badge-sm badge-outline uppercase tracking-widest">
                      Source detected
                    </span>
                    <span class="text-base-content">{@selected_source.label}</span>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-outline gap-2 rounded-full"
                    phx-click="random_from_source"
                    phx-value-source={@selected_source.id}
                    phx-disable-with="Searching..."
                    disabled={@importing}
                  >
                    <.icon name="hero-sparkles" class="h-4 w-4" />
                    Random from {@selected_source.label}
                  </button>
                </div>
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
                  class="btn btn-primary gap-2 phx-submit-loading:loading"
                >
                  <.icon name="hero-arrow-down-on-square" class="h-4 w-4" /> Import Article
                </.button>
              </div>
            </.form>
            <div class="border-t border-base-200 pt-6 space-y-6">
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <p class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                    Library
                  </p>
                  <h2 class="flex flex-wrap items-center gap-3 text-2xl font-semibold text-base-content">
                    Your articles
                    <span class="badge badge-lg badge-outline font-semibold text-base-content/80">
                      {@articles_count}
                    </span>
                  </h2>
                  <p class="mt-1 text-sm text-base-content/65">
                    Search, filter by topic, then continue reading where you left off.
                  </p>
                </div>
                <div class="flex flex-col items-stretch gap-3 sm:items-end">
                  <div class="flex flex-wrap items-center justify-end gap-3">
                    <.link
                      navigate={~p"/articles/recommendations"}
                      class="btn btn-sm btn-ghost gap-2"
                    >
                      <.icon name="hero-sparkles" class="h-4 w-4" /> Recommendations
                    </.link>
                    <.async_result :let={count} assign={@recommended_count}>
                      <:loading>
                        <span class="badge badge-sm badge-ghost">
                          <span class="loading loading-spinner loading-xs"></span>
                        </span>
                      </:loading>
                      <:failed>
                        <span class="badge badge-sm badge-ghost">0</span>
                      </:failed>
                      <span class={[
                        "badge badge-sm font-semibold text-base-content/80",
                        count > 0 && "badge-primary badge-outline"
                      ]}>
                        {count}
                      </span>
                    </.async_result>
                  </div>
                  <.search_input
                    id="article-search"
                    value={@query}
                    placeholder="Title, URL, or source"
                    event="search"
                    clear_event="clear_search"
                    debounce={250}
                    class="w-full sm:w-80"
                    disabled={@importing}
                  />
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
                  All
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
                  {Topics.topic_name(@target_language, topic)}
                </button>
              </div>

              <div :if={@articles_loading} class="grid gap-6 md:grid-cols-2">
                <.article_skeleton :for={_ <- 1..4} />
              </div>

              <.card_grid :if={not @articles_loading} id="articles" phx-update="stream">
                <.list_empty_state
                  id="articles-empty-state"
                  class={if @articles_count > 0, do: "md:col-span-2 hidden", else: "md:col-span-2"}
                >
                  <:title>No articles yet.</:title>
                  <:description>
                    Start building your reading queue by importing an article.
                  </:description>
                  <:actions>
                    <.link href="#article-import-form" class="btn btn-sm btn-primary">
                      Import your first one
                    </.link>
                  </:actions>
                </.list_empty_state>

                <.card
                  :for={{dom_id, article} <- @streams.articles}
                  id={dom_id}
                  variant={:panel}
                  hover
                  class="relative group h-full"
                >
                  <:header>
                    <% topics = top_topics(article) %>
                    <div class="flex items-start justify-between gap-3">
                      <div class="flex flex-col gap-2">
                        <div class="flex flex-wrap items-center gap-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                          <span class="inline-flex items-center gap-2">
                            <span class="badge badge-sm badge-outline">
                              {article.source || URI.parse(article.url).host}
                            </span>
                            <span class="badge badge-sm badge-primary badge-outline uppercase tracking-wide">
                              {article.language}
                            </span>
                          </span>
                          <span class="text-base-content/40">•</span>
                          <span class="text-base-content/60">
                            Imported {format_timestamp(article.inserted_at)}
                          </span>
                        </div>
                        <.link
                          navigate={~p"/articles/#{article}"}
                          class="card-title text-lg font-semibold leading-snug text-base-content no-underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/60 rounded"
                        >
                          {article.title || "Untitled article"}
                        </.link>
                      </div>

                      <details class="dropdown dropdown-end opacity-100 sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100 transition">
                        <summary class="btn btn-ghost btn-sm btn-circle" aria-label="Article actions">
                          <.icon name="hero-ellipsis-vertical" class="h-5 w-5" />
                        </summary>
                        <ul class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 border border-base-300 p-2 shadow-lg">
                          <li>
                            <.link navigate={~p"/articles/#{article}"}>
                              <.icon name="hero-arrow-right" class="h-4 w-4" /> Continue reading
                            </.link>
                          </li>
                          <li>
                            <.link href={article.url} target="_blank">
                              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                              View original
                            </.link>
                          </li>
                          <li>
                            <button
                              type="button"
                              class="text-error"
                              phx-click="delete"
                              phx-value-id={article.id}
                              phx-confirm="Remove this article from your library?"
                            >
                              <.icon name="hero-trash" class="h-4 w-4" /> Remove
                            </button>
                          </li>
                        </ul>
                      </details>
                    </div>

                    <div :if={topics != []} class="flex flex-wrap items-center gap-2">
                      <span class="text-xs font-semibold uppercase tracking-widest text-base-content/50">
                        Topics
                      </span>
                      <span
                        :for={topic <- topics}
                        class="badge badge-sm rounded-full border border-primary/20 bg-primary/10 text-primary"
                      >
                        {Topics.topic_name(article.language, topic.topic)}
                      </span>
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
                    <div class="flex items-center justify-between gap-3 w-full">
                      <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/60">
                        <span :if={article.unique_word_count} class="badge badge-sm badge-ghost">
                          {article.unique_word_count} unique words
                        </span>
                      </div>
                      <.link navigate={~p"/articles/#{article}"} class="btn btn-sm btn-primary gap-2">
                        Continue <.icon name="hero-arrow-right" class="h-4 w-4" />
                      </.link>
                    </div>
                  </:actions>
                </.card>
              </.card_grid>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp article_skeleton(assigns) do
    ~H"""
    <div class="card surface-panel animate-pulse">
      <div class="card-body space-y-4">
        <div class="flex items-center gap-2">
          <div class="h-5 w-20 rounded bg-base-300"></div>
          <div class="h-5 w-12 rounded bg-base-300"></div>
        </div>
        <div class="h-6 w-3/4 rounded bg-base-300"></div>
        <div class="space-y-2">
          <div class="h-4 w-full rounded bg-base-300"></div>
          <div class="h-4 w-5/6 rounded bg-base-300"></div>
          <div class="h-4 w-2/3 rounded bg-base-300"></div>
        </div>
        <div class="flex items-center justify-between pt-2">
          <div class="h-5 w-24 rounded bg-base-300"></div>
          <div class="h-8 w-24 rounded bg-base-300"></div>
        </div>
      </div>
    </div>
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

  def handle_event("search", %{"q" => query}, socket) do
    query = String.trim(to_string(query))

    path =
      if query == "" do
        ~p"/articles"
      else
        ~p"/articles?q=#{URI.encode(query)}"
      end

    {:noreply,
     socket
     |> assign(:query, query)
     |> load_articles_async()
     |> push_patch(to: path, replace: true)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:query, "")
     |> load_articles_async()
     |> push_patch(to: ~p"/articles", replace: true)}
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
    {:noreply,
     socket
     |> assign(:selected_topic, nil)
     |> load_articles_async()}
  end

  def handle_event("filter_topic", %{"topic" => topic}, socket) do
    {:noreply,
     socket
     |> assign(:selected_topic, topic)
     |> load_articles_async()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <-
           Content.delete_article_for_user(socket.assigns.current_scope.user.id, article_id) do
      user_id = socket.assigns.current_scope.user.id

      {:noreply,
       socket
       |> update(:articles_count, &max(&1 - 1, 0))
       |> stream_delete(:articles, %{id: article_id})
       |> assign_async(:recommended_count, fn ->
         {:ok,
          %{recommended_count: Content.get_recommended_count(user_id, @recommendations_limit)}}
       end)
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

  defp import_article(socket, url, opts \\ []) do
    trimmed = String.trim(to_string(url || ""))

    if trimmed == "" do
      {:error, put_flash(socket, :error, "Please provide a URL.")}
    else
      process_article_import(socket, trimmed, opts)
    end
  end

  defp process_article_import(socket, trimmed, opts) do
    user = socket.assigns.current_scope.user
    socket = assign(socket, importing: true)

    case ArticleImporter.import_from_url(user, trimmed) do
      {:ok, article, status} -> handle_successful_import(socket, article, status, trimmed, opts)
      {:error, reason} -> handle_import_error(socket, reason)
    end
  end

  defp handle_successful_import(socket, article, status, trimmed, opts) do
    count_delta = if status == :new, do: 1, else: 0
    keep_url? = opts[:keep_url]
    form_payload = if keep_url?, do: %{"url" => trimmed}, else: %{"url" => ""}
    selected_source = if keep_url?, do: socket.assigns.selected_source, else: nil
    flash_message = opts[:flash] || "Imported #{article.title || article.url}"

    socket =
      socket
      |> put_flash(:info, flash_message)
      |> assign(
        importing: false,
        selected_source: selected_source,
        form: to_form(form_payload, as: :article),
        articles_count: socket.assigns.articles_count + count_delta
      )

    socket =
      if socket.assigns.selected_topic || socket.assigns.query != "" do
        load_articles_async(socket)
      else
        stream_insert(socket, :articles, article, at: 0)
      end

    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign_async(:recommended_count, fn ->
        {:ok,
         %{recommended_count: Content.get_recommended_count(user_id, @recommendations_limit)}}
      end)

    {:ok, socket}
  end

  defp handle_import_error(socket, reason) do
    {:error,
     socket
     |> put_flash(:error, humanize_error(reason))
     |> assign(importing: false)}
  end

  defp load_articles_async(socket) do
    user_id = socket.assigns.current_scope.user.id
    query = socket.assigns.query
    topic = socket.assigns.selected_topic

    socket
    |> assign(:articles_loading, true)
    |> start_async(:load_articles, fn ->
      articles = Content.list_articles_for_user(user_id, query: query, topic: topic)
      %{articles: articles, count: length(articles)}
    end)
  end

  def handle_async(:load_articles, {:ok, %{articles: articles, count: count}}, socket) do
    {:noreply,
     socket
     |> assign(:articles_loading, false)
     |> assign(:articles_count, count)
     |> stream(:articles, articles, reset: true)}
  end

  def handle_async(:load_articles, {:exit, reason}, socket) do
    Logger.error("ArticleLive: Failed to load articles: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:articles_loading, false)
     |> put_flash(:error, "Failed to load articles: #{inspect(reason)}")}
  end

  defp top_topics(article) do
    case Map.get(article, :article_topics) do
      %Ecto.Association.NotLoaded{} ->
        []

      topics when is_list(topics) ->
        topics
        |> Enum.sort_by(fn topic -> topic_confidence(topic) end, :desc)
        |> Enum.take(3)

      _ ->
        []
    end
  end

  defp topic_confidence(%{confidence: %Decimal{} = confidence}), do: Decimal.to_float(confidence)
  defp topic_confidence(%{confidence: confidence}) when is_number(confidence), do: confidence
  defp topic_confidence(_), do: 0.0

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

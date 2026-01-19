defmodule LanglerWeb.StudyLive.Index do
  @moduledoc """
  LiveView for spaced repetition study sessions.
  """

  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.Wiktionary.Conjugations
  alias Langler.Repo
  alias Langler.Study
  alias Langler.Study.FSRS
  alias Langler.Vocabulary
  alias Langler.Vocabulary.Word
  alias MapSet
  alias Phoenix.LiveView.JS
  require Logger

  @filters [
    %{id: :now, label: "Due now"},
    %{id: :today, label: "Due today"},
    %{id: :all, label: "All words"}
  ]

  @quality_buttons [
    %{score: 0, label: "Again", class: "btn-error"},
    %{score: 2, label: "Hard", class: "btn-warning"},
    %{score: 3, label: "Good", class: "btn-primary"},
    %{score: 4, label: "Easy", class: "btn-success"}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    items = Study.list_items_for_user(scope.user.id)
    filter = :now
    visible_items = filter_items(items, filter)

    # Calculate user level and get recommendations
    user_level = Study.get_user_vocabulary_level(scope.user.id)
    user_id = scope.user.id

    {:ok,
     socket
     |> assign(:current_user, scope.user)
     |> assign(:filters, @filters)
     |> assign(:filter, filter)
     |> assign(:search_query, "")
     |> assign(:quality_buttons, @quality_buttons)
     |> assign(:stats, build_stats(items))
     |> assign(:all_items, items)
     |> assign(:visible_count, length(visible_items))
     |> assign(:flipped_cards, MapSet.new())
     |> assign(:expanded_conjugations, MapSet.new())
     |> assign(:conjugations_loading, MapSet.new())
     |> assign(:definitions_loading, MapSet.new())
     |> assign(:user_level, user_level)
     |> assign_async(:recommended_articles, fn ->
       {:ok, %{recommended_articles: Content.get_recommended_articles_for_user(user_id, 5)}}
     end)
     |> stream(:items, visible_items)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <div class="surface-panel card section-card bg-base-100/95">
          <div class="card-body gap-6">
            <div class="section-header">
              <p class="section-header__eyebrow">Study overview</p>
              <h1 class="section-header__title">Stay consistent with your deck</h1>
              <p class="section-header__lede">
                Track upcoming reviews and keep tabs on due cards with quick filters.
              </p>
            </div>

            <div class="kpi-grid">
              <div class="kpi-card">
                <p class="kpi-card__title">Due now</p>
                <p class="kpi-card__value text-primary">{@stats.due_now}</p>
                <p class="kpi-card__meta">Ready for immediate review</p>
              </div>

              <div class="kpi-card">
                <p class="kpi-card__title">Due today</p>
                <p class="kpi-card__value text-secondary">{@stats.due_today}</p>
                <p class="kpi-card__meta">Includes overdue &amp; later today</p>
              </div>

              <div class="kpi-card">
                <p class="kpi-card__title">Total tracked</p>
                <p class="kpi-card__value text-base-content">{@stats.total}</p>
                <p class="kpi-card__meta">Words in your study bank</p>
              </div>
            </div>

            <div class="space-y-1">
              <div class="flex items-center justify-between text-xs font-semibold uppercase tracking-widest text-base-content/60">
                <span>Daily progress</span>
                <span>{@stats.completion}% caught up</span>
              </div>
              <progress
                value={@stats.completion}
                max="100"
                class="progress progress-primary h-2 w-full"
                aria-label="Daily completion"
              />
            </div>

            <div class="flex flex-wrap gap-3 text-sm font-semibold">
              <.link
                navigate={~p"/study/session"}
                class="btn btn-sm btn-primary text-white shadow transition duration-200 hover:-translate-y-0.5 hover:shadow-lg active:translate-y-0 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
              >
                <.icon name="hero-play" class="h-4 w-4" /> Start Study Session
              </.link>
              <.link
                navigate={~p"/articles"}
                class="btn btn-sm btn-ghost border border-dashed border-base-300 transition duration-200 hover:bg-base-200/70 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
              >
                Go to library
              </.link>
              <.link
                navigate={~p"/articles/new"}
                class="btn btn-sm btn-ghost border border-dashed border-base-300 transition duration-200 hover:bg-base-200/70 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
              >
                Import article
              </.link>
            </div>

            <div class="flex flex-col gap-3 rounded-2xl border border-base-200 bg-base-200/30 p-4 backdrop-blur sm:flex-row sm:items-center sm:justify-between">
              <div class="space-y-1">
                <p class="text-sm font-semibold text-base-content/80">Search your deck</p>
                <p class="text-xs text-base-content/60">
                  Type a lemma to narrow results across filters.
                </p>
              </div>
              <form id="study-search-form" phx-change="search_items" class="w-full sm:w-auto">
                <label class="input input-bordered flex items-center gap-2 w-full sm:w-96 focus-within:ring focus-within:ring-primary/30 phx-change-loading:opacity-70">
                  <.icon name="hero-magnifying-glass" class="h-4 w-4 text-base-content/60" />
                  <input
                    type="text"
                    name="search_query"
                    id="study-search-input"
                    value={@search_query}
                    placeholder="Search words…"
                    phx-debounce="300"
                    autocomplete="off"
                    class="grow"
                    aria-label="Search words"
                  />
                  <button
                    :if={@search_query != ""}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click={JS.push("clear_search") |> JS.focus(to: "#study-search-input")}
                    aria-label="Clear search"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </label>
              </form>
            </div>

            <div class="tabs tabs-boxed bg-base-200/70 p-1 text-sm font-semibold text-base-content/70 overflow-x-auto">
              <button
                :for={filter <- @filters}
                type="button"
                class={[
                  "tab tab-sm sm:tab-lg rounded-xl whitespace-nowrap transition duration-200 focus-visible:ring focus-visible:ring-primary/40",
                  @filter == filter.id && "tab-active bg-base-100 text-base-content shadow"
                ]}
                phx-click="set_filter"
                phx-value-filter={filter.id}
              >
                {filter.label}
              </button>
            </div>
          </div>
        </div>

        <%!-- Recommended Articles Section --%>
        <.async_result :let={recommended_articles} assign={@recommended_articles}>
          <:loading>
            <div :if={@filter == :now} class="card section-card bg-base-100/95">
              <div class="card-body gap-4">
                <div class="flex items-center gap-2">
                  <span class="loading loading-spinner loading-sm"></span>
                  <span class="text-sm text-base-content/70">Loading recommendations...</span>
                </div>
              </div>
            </div>
          </:loading>
          <:failed :let={_failure}>
            <div :if={@filter == :now} class="card section-card bg-base-100/95">
              <div class="card-body gap-4">
                <p class="text-sm text-base-content/70">Unable to load recommendations.</p>
              </div>
            </div>
          </:failed>
          <div
            :if={recommended_articles != [] && @filter == :now}
            class="card section-card bg-base-100/95"
          >
            <div class="card-body gap-4">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="space-y-1">
                  <h2 class="card-title">
                    <.icon name="hero-light-bulb" class="h-6 w-6 text-primary" /> Recommended reading
                    <span class="badge badge-primary badge-sm">
                      {@user_level.cefr_level || "Learning"}
                    </span>
                  </h2>
                  <p class="text-sm text-base-content/70">
                    Hand-picked articles matched to your vocabulary level.
                  </p>
                </div>
                <.link
                  navigate={~p"/articles"}
                  class="btn btn-sm btn-ghost border border-dashed border-base-300 transition duration-200 hover:bg-base-200/70 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
                >
                  Browse more
                </.link>
              </div>

              <div class="grid gap-3 sm:grid-cols-2">
                <.card
                  :for={rec <- recommended_articles}
                  variant={:border}
                  hover
                  class="bg-base-100/80"
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0">
                      <.link
                        href={rec.article.url}
                        target="_blank"
                        class="inline-flex items-start gap-2 font-semibold text-base-content hover:text-primary focus-visible:outline-none focus-visible:ring focus-visible:ring-primary/40 rounded"
                      >
                        <span class="min-w-0 break-words">{rec.article.title}</span>
                        <.icon
                          name="hero-arrow-top-right-on-square"
                          class="mt-0.5 h-4 w-4 shrink-0 opacity-60"
                        />
                      </.link>
                      <div class="mt-2 flex flex-wrap gap-2">
                        <span class="badge badge-sm">
                          Level {trunc(rec.article.difficulty_score || 0)}
                        </span>
                        <span
                          :if={rec.article.avg_sentence_length}
                          class="badge badge-sm badge-outline"
                        >
                          {trunc(rec.article.avg_sentence_length)} words/sentence
                        </span>
                      </div>
                    </div>
                    <div class="text-right">
                      <div class="text-xs font-semibold uppercase tracking-widest text-base-content/50">
                        Match
                      </div>
                      <div class="text-lg font-semibold text-primary">
                        {trunc((rec.score || 0) * 100)}%
                      </div>
                    </div>
                  </div>

                  <progress
                    value={trunc((rec.score || 0) * 100)}
                    max="100"
                    class="progress progress-primary h-2 w-full"
                    aria-label="Article match"
                  />

                  <:actions>
                    <div class="flex items-center justify-between gap-3 w-full">
                      <div class="text-xs text-base-content/60">
                        Import to your library to start highlighting.
                      </div>
                      <button
                        type="button"
                        phx-click="import_article"
                        phx-value-id={rec.article.id}
                        phx-disable-with="Importing…"
                        class="btn btn-xs btn-primary text-white transition duration-200 active:scale-[0.99] phx-click-loading:opacity-70 phx-click-loading:cursor-wait"
                      >
                        Import
                      </button>
                    </div>
                  </:actions>
                </.card>
              </div>
            </div>
          </div>
        </.async_result>

        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="space-y-1">
            <h2 class="text-base font-semibold text-base-content">Cards</h2>
            <p class="text-sm text-base-content/70">
              Showing <span class="font-semibold text-base-content">{@visible_count}</span>
              <span class="text-base-content/50">·</span>
              <span class="badge badge-sm badge-outline">{filter_label(@filter)}</span>
            </p>
          </div>
          <div class="text-xs text-base-content/60">
            Tip: click the word to copy, then tap to reveal.
          </div>
        </div>

        <div class="space-y-4">
          <div
            id="study-items"
            phx-update="stream"
            class="space-y-4"
          >
            <div
              id="study-empty-state"
              class="hidden only:flex flex-col items-center justify-center rounded-3xl border border-dashed border-base-300 bg-base-100/80 px-8 py-10 text-center text-base-content/70"
            >
              <p class="text-lg font-semibold text-base-content">
                <%= cond do %>
                  <% @search_query != "" -> %>
                    No matches found
                  <% @filter == :now -> %>
                    You're fully caught up
                  <% true -> %>
                    No cards to show
                <% end %>
              </p>
              <p class="text-sm">
                <%= cond do %>
                  <% @search_query != "" -> %>
                    Try a different spelling, or clear your search to see everything again.
                  <% @filter == :now -> %>
                    Switch filters or import more words from an article.
                  <% true -> %>
                    Switch filters or import more words from an article.
                <% end %>
              </p>
              <div class="mt-4 flex flex-wrap justify-center gap-2">
                <button
                  :if={@search_query != ""}
                  id="study-empty-clear-search"
                  type="button"
                  class="btn btn-sm btn-ghost border border-dashed border-base-300 transition duration-200 hover:bg-base-200/70 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
                  phx-click={JS.push("clear_search") |> JS.focus(to: "#study-search-input")}
                >
                  Clear search
                </button>
                <.link
                  navigate={~p"/articles"}
                  class="btn btn-sm btn-primary text-white transition duration-200 hover:-translate-y-0.5 hover:shadow-lg active:translate-y-0 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40"
                >
                  Explore library
                </.link>
              </div>
            </div>

            <.card
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              variant={:panel}
              hover
              class="border border-base-200 animate-fade-in"
            >
              <button
                type="button"
                phx-click="toggle_card"
                phx-value-id={item.id}
                phx-hook="WordCardToggle"
                id={"study-card-#{item.id}"}
                data-item-id={item.id}
                class="group relative w-full rounded-2xl border border-dashed border-base-200 bg-base-100/80 p-4 text-left transition duration-300 hover:border-primary/40 active:scale-[0.995] focus-visible:ring focus-visible:ring-primary/40 phx-click-loading:opacity-70"
              >
                <% flipped = MapSet.member?(@flipped_cards, item.id) %>
                <% definitions = item.word && (item.word.definitions || []) %>
                <div class="relative min-h-[16rem]">
                  <div class={[
                    "space-y-4 transition-opacity duration-300",
                    flipped && "hidden"
                  ]}>
                    <div class="flex flex-wrap items-start justify-between gap-4">
                      <div class="flex flex-col gap-1">
                        <p
                          class="inline-flex items-center gap-2 text-3xl font-semibold text-base-content cursor-pointer transition hover:text-primary"
                          phx-hook="CopyToClipboard"
                          data-copy-text={item.word && (item.word.lemma || item.word.normalized_form)}
                          title="Click to copy"
                          id={"study-card-word-#{item.id}"}
                        >
                          <span>{item.word && (item.word.lemma || item.word.normalized_form)}</span>
                          <span
                            class="opacity-0 text-primary/80 transition-opacity duration-200 group-hover:opacity-100 pointer-events-none"
                            aria-hidden="true"
                          >
                            <.icon name="hero-clipboard-document" class="h-5 w-5" />
                          </span>
                        </p>
                        <p class="text-sm text-base-content/70">
                          Next review {format_due_label(item.due_date)}
                        </p>
                      </div>
                      <span class={[
                        "badge badge-lg border",
                        due_badge_class(item.due_date)
                      ]}>
                        {due_status_label(item.due_date)}
                      </span>
                    </div>

                    <div class="flex flex-wrap gap-6 text-sm text-base-content/70">
                      <div>
                        <p class="font-semibold text-base-content">Ease factor</p>
                        <p>{format_decimal(item.ease_factor || 2.5)}</p>
                      </div>
                      <div>
                        <p class="font-semibold text-base-content">Interval</p>
                        <p>{interval_label(item.interval)}</p>
                      </div>
                      <div>
                        <p class="font-semibold text-base-content">Repetitions</p>
                        <p>{item.repetitions || 0}</p>
                      </div>
                      <div>
                        <p class="font-semibold text-base-content">Recent history</p>
                        <div class="flex gap-1">
                          <span
                            :for={score <- recent_history(item.quality_history)}
                            class={[
                              "h-2.5 w-6 rounded-full bg-base-300",
                              history_pill_class(score)
                            ]}
                            aria-label={"Score #{score}"}
                          />
                        </div>
                      </div>
                    </div>
                    <p class="text-xs font-semibold uppercase tracking-widest text-base-content/50">
                      Tap to reveal definition
                    </p>
                  </div>

                  <div class={[
                    "flex flex-col gap-4 rounded-xl border border-primary/30 bg-primary/5 p-4 text-base-content transition-opacity duration-300",
                    flipped && "block",
                    !flipped && "hidden"
                  ]}>
                    <p class="text-sm font-semibold uppercase tracking-widest text-primary/70">
                      Definition
                    </p>
                    <%= if MapSet.member?(@definitions_loading || MapSet.new(), item.id) do %>
                      <div class="flex items-center gap-2">
                        <span class="loading loading-spinner loading-sm"></span>
                        <span class="text-sm text-base-content/70">Loading definition...</span>
                      </div>
                    <% else %>
                      <ol class="space-y-3 text-sm leading-relaxed text-base-content/90">
                        <li
                          :for={{definition, idx} <- Enum.with_index(definitions, 1)}
                          class="break-words"
                        >
                          <span class="font-semibold text-primary/80">{idx}.</span>
                          <span class="ml-2 break-words">{definition}</span>
                        </li>
                      </ol>
                      <p :if={definitions == []} class="text-sm text-base-content/70">
                        We haven't saved a definition yet for this word. Tap refresh in the reader to fetch one.
                      </p>
                    <% end %>
                    <p class="text-xs text-base-content/60">Tap again to return.</p>
                  </div>
                </div>
              </button>

              <:conjugations>
                <div
                  :if={
                    item.word &&
                      (verb?(item.word.part_of_speech) || looks_like_spanish_verb?(item.word))
                  }
                  class="rounded-2xl border border-dashed border-primary/30 bg-primary/5 p-4"
                >
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p class="text-sm font-semibold uppercase tracking-widest text-primary/80">
                        Verb conjugations
                      </p>
                      <p class="text-xs text-primary/60">
                        Peek at every tense to reinforce patterns before you review.
                      </p>
                    </div>
                    <button
                      type="button"
                      class="btn btn-sm btn-primary btn-soft transition duration-200 hover:-translate-y-0.5 active:translate-y-0 active:scale-[0.99] focus-visible:ring focus-visible:ring-primary/40 phx-click-loading:opacity-70"
                      phx-click="toggle_conjugations"
                      phx-value-word-id={item.word.id}
                    >
                      <.icon name="hero-table-cells" class="h-4 w-4" />
                      {if MapSet.member?(@expanded_conjugations, item.word.id),
                        do: "Hide",
                        else: "View"} conjugations
                    </button>
                  </div>

                  <div
                    :if={MapSet.member?(@expanded_conjugations, item.word.id)}
                    id={"study-conjugations-#{item.word.id}"}
                    class="mt-4 rounded-xl border border-base-200 bg-base-100/90 p-4 shadow-inner"
                  >
                    <%= if MapSet.member?(@conjugations_loading || MapSet.new(), item.word.id) do %>
                      <div class="flex items-center gap-2">
                        <span class="loading loading-spinner loading-sm"></span>
                        <span class="text-sm text-base-content/70">Loading conjugations...</span>
                      </div>
                    <% else %>
                      <.conjugation_table conjugations={item.word.conjugations} />
                    <% end %>
                  </div>
                </div>
              </:conjugations>

              <:actions>
                <.card_rating item_id={item.id} buttons={@quality_buttons} />
              </:actions>
            </.card>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("set_filter", %{"filter" => filter}, socket) do
    filter = parse_filter(filter)
    visible = filter_items(socket.assigns.all_items, filter, socket.assigns.search_query)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:visible_count, length(visible))
     |> stream(:items, visible, reset: true)}
  end

  def handle_event(
        "rate_word",
        %{"quality" => quality} = params,
        socket
      ) do
    item_id = params["item_id"] || params["item-id"]

    with {:ok, item} <- find_item(socket.assigns.all_items, item_id),
         rating <- parse_quality(quality),
         {:ok, updated} <- Study.review_item(item, rating) do
      all_items = replace_item(socket.assigns.all_items, updated)
      stats = build_stats(all_items)
      visible = filter_items(all_items, socket.assigns.filter, socket.assigns.search_query)

      {:noreply,
       socket
       |> assign(:all_items, all_items)
       |> assign(:stats, stats)
       |> assign(:visible_count, length(visible))
       |> stream(:items, visible, reset: true)
       |> put_flash(
         :info,
         "Logged review for #{item.word && (item.word.lemma || item.word.normalized_form)}"
       )}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to rate card: #{inspect(reason)}")}
    end
  end

  def handle_event("search_items", params, socket) do
    query =
      params
      |> extract_search_query()
      |> String.trim()

    visible = filter_items(socket.assigns.all_items, socket.assigns.filter, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:visible_count, length(visible))
     |> stream(:items, visible, reset: true)}
  end

  def handle_event("clear_search", _params, socket) do
    visible = filter_items(socket.assigns.all_items, socket.assigns.filter, "")

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:visible_count, length(visible))
     |> stream(:items, visible, reset: true)}
  end

  def handle_event("import_article", %{"id" => discovered_article_id_str}, socket) do
    with {discovered_article_id, ""} <- Integer.parse(discovered_article_id_str),
         _discovered_article <- Content.get_discovered_article(discovered_article_id),
         {:ok, _} <-
           Content.mark_discovered_article_imported(
             discovered_article_id,
             socket.assigns.current_user.id
           ) do
      # Refresh recommendations
      user_level = Study.get_user_vocabulary_level(socket.assigns.current_user.id)
      user_id = socket.assigns.current_user.id

      {:noreply,
       socket
       |> assign(:user_level, user_level)
       |> assign_async(:recommended_articles, fn ->
         {:ok, %{recommended_articles: Content.get_recommended_articles_for_user(user_id, 5)}}
       end)
       |> put_flash(:info, "Article imported successfully")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to import article")}
    end
  end

  def handle_event("toggle_card", %{"id" => id}, socket) do
    with {item_id, ""} <- Integer.parse(to_string(id)),
         {:ok, item} <- find_item(socket.assigns.all_items, item_id) do
      flipped = toggle_set_member(socket.assigns.flipped_cards, item_id)
      flipped_state = MapSet.member?(flipped, item_id)

      # Check if we need to fetch definitions
      socket = maybe_start_definition_fetch(socket, item_id, flipped_state, item)

      dom_id = "items-#{item_id}"

      {:noreply,
       socket
       |> assign(:flipped_cards, flipped)
       |> stream_insert(:items, item, dom_id: dom_id)
       |> push_event("study:card-toggled", %{id: item_id, flipped: flipped_state})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_conjugations", %{"word-id" => word_id_str}, socket) do
    case fetch_conjugation_item(socket.assigns.all_items, word_id_str) do
      {:ok, word_id, item} ->
        expanded = toggle_set_member(socket.assigns.expanded_conjugations, word_id)

        socket =
          socket
          |> assign(:expanded_conjugations, expanded)

        # If expanding and conjugations are missing, fetch them async
        expanded_state = MapSet.member?(expanded, word_id)
        socket = maybe_start_conjugation_fetch(socket, word_id, expanded_state, item)

        # Update the item in the stream immediately (conjugations will update via handle_async if async was started)
        dom_id = "items-#{item.id}"

        {:noreply,
         socket
         |> stream_insert(:items, item, dom_id: dom_id)}

      :error ->
        {:noreply, socket}
    end
  end

  defp filter_label(filter) do
    Enum.find_value(@filters, "All words", fn %{id: id, label: label} ->
      if id == filter, do: label
    end)
  end

  def handle_async({:fetch_definitions, item_id}, {:ok, {_item_id, entry, word, flags}}, socket) do
    definitions = List.wrap(entry.definitions)
    updates = build_definition_updates(flags, entry, definitions)

    case find_item(socket.assigns.all_items, item_id) do
      {:ok, item} ->
        {:ok, updated_item} = apply_word_updates(item, word, updates)
        updated_items = replace_item(socket.assigns.all_items, updated_item)
        dom_id = "items-#{item_id}"

        {:noreply,
         socket
         |> assign(:all_items, updated_items)
         |> assign(
           :definitions_loading,
           MapSet.delete(socket.assigns[:definitions_loading] || MapSet.new(), item_id)
         )
         |> stream_insert(:items, updated_item, dom_id: dom_id)}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(
           :definitions_loading,
           MapSet.delete(socket.assigns[:definitions_loading] || MapSet.new(), item_id)
         )}
    end
  end

  def handle_async({:fetch_definitions, item_id}, {:exit, reason}, socket) do
    Logger.warning(
      "StudyLive: failed to fetch definitions for item_id=#{item_id}: #{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(
       :definitions_loading,
       MapSet.delete(socket.assigns[:definitions_loading] || MapSet.new(), item_id)
     )}
  end

  def handle_async({:fetch_conjugations, word_id}, {:ok, conjugations_map}, socket) do
    Logger.debug("StudyLive: handle_async received conjugations for word_id=#{word_id}: #{inspect(conjugations_map)}")

    case conjugations_map do
      {:error, reason} ->
        Logger.warning(
          "StudyLive: failed to fetch conjugations for word_id=#{word_id}: #{inspect(reason)}"
        )

        {:noreply, clear_conjugations_loading(socket, word_id)}

      conjugations when is_map(conjugations) ->
        handle_conjugations_success(socket, word_id, conjugations)

      _ ->
        Logger.warning(
          "StudyLive: unexpected conjugations format for word_id=#{word_id}: #{inspect(conjugations_map)}"
        )

        {:noreply, socket}
    end
  end

  def handle_async({:fetch_conjugations, word_id}, {:exit, reason}, socket) do
    Logger.warning(
      "StudyLive: failed to fetch conjugations for word_id=#{word_id}: #{inspect(reason)}"
    )

    {:noreply,
     socket
     |> assign(
       :conjugations_loading,
       MapSet.delete(socket.assigns[:conjugations_loading] || MapSet.new(), word_id)
     )}
  end

  defp extract_search_query(%{"search_query" => query}) when is_binary(query), do: query
  defp extract_search_query(%{"search-query" => query}) when is_binary(query), do: query
  defp extract_search_query(_), do: ""

  defp parse_filter(value) do
    case value do
      "today" -> :today
      "all" -> :all
      _ -> :now
    end
  end

  defp parse_quality(value) when is_binary(value) do
    value
    |> String.to_integer()
    |> FSRS.rating_from_quality()
  rescue
    ArgumentError -> :good
  end

  defp filter_items(items, filter, query \\ "") do
    now = DateTime.utc_now()
    end_of_day = end_of_day(now)
    downcased_query = String.downcase(query || "")

    Enum.filter(items, fn item ->
      matches_filter =
        case filter do
          :now -> due_now?(item, now)
          :today -> due_today?(item, end_of_day)
          :all -> true
        end

      matches_query = downcased_query == "" or match_query?(item.word, downcased_query)

      matches_filter and matches_query
    end)
  end

  defp match_query?(%Word{} = word, query) do
    lemma = word.lemma || ""
    normalized = word.normalized_form || ""

    String.contains?(String.downcase(lemma), query) or
      String.contains?(String.downcase(normalized), query)
  end

  defp match_query?(_, _), do: false

  defp build_stats(items) do
    now = DateTime.utc_now()
    end_of_day = end_of_day(now)

    due_now = Enum.count(items, &due_now?(&1, now))
    total = length(items)

    completion =
      if total == 0 do
        100
      else
        Float.round((total - due_now) / total * 100, 0)
      end

    %{
      due_now: due_now,
      due_today: Enum.count(items, &due_today?(&1, end_of_day)),
      total: total,
      completion: trunc(completion)
    }
  end

  defp due_now?(%{due_date: nil}, _now), do: true

  defp due_now?(%{due_date: due}, now) do
    DateTime.compare(due, now) != :gt
  end

  defp due_today?(item, end_of_day) do
    case item.due_date do
      nil -> true
      due -> DateTime.compare(due, end_of_day) != :gt
    end
  end

  defp end_of_day(now) do
    date = DateTime.to_date(now)
    DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
  end

  defp replace_item(items, updated) do
    Enum.map(items, fn item ->
      if item.id == updated.id, do: updated, else: item
    end)
  end

  defp toggle_set_member(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end

  defp fetch_conjugation_item(items, word_id_str) do
    with {word_id, ""} <- Integer.parse(to_string(word_id_str)),
         {:ok, item} <- find_item_by_word_id(items, word_id),
         true <- not is_nil(item.word) do
      {:ok, word_id, item}
    else
      _ -> :error
    end
  end

  defp missing_conjugations?(word) do
    is_nil(word.conjugations) or word.conjugations == %{}
  end

  defp fetch_conjugations_with_cache(word, lookup_lemma) do
    # First check if word already has conjugations in DB
    if word.conjugations && word.conjugations != %{} do
      # Use DB value and populate ETS cache
      Logger.debug("StudyLive: using DB conjugations for word_id=#{word.id}")
      populate_ets_cache(lookup_lemma, word.language, word.conjugations)
      word.conjugations
    else
      # Fetch from external source (which uses ETS cache)
      Logger.debug("StudyLive: fetching conjugations from external for word_id=#{word.id}, lemma=#{lookup_lemma}")
      case Conjugations.fetch_conjugations(lookup_lemma, word.language) do
        {:ok, conjugations_map} ->
          Logger.debug("StudyLive: successfully fetched conjugations for word_id=#{word.id}")
          conjugations_map
        {:error, reason} ->
          Logger.warning("StudyLive: failed to fetch conjugations for word_id=#{word.id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.error("StudyLive: exception fetching conjugations for word_id=#{word.id}: #{inspect(e)}")
      {:error, :exception}
  catch
    :exit, reason ->
      Logger.error("StudyLive: exit while fetching conjugations for word_id=#{word.id}: #{inspect(reason)}")
      {:error, :exit}
  end

  defp populate_ets_cache(lemma, language, conjugations) do
    normalized_language = String.downcase(language)
    cache_key = {normalized_language, String.downcase(lemma)}

    # Get cache table from config (same as Conjugations module)
    config = Application.get_env(:langler, Langler.External.Dictionary.Wiktionary, [])
    table = Keyword.get(config, :conjugation_cache_table, :wiktionary_conjugation_cache)
    ttl = Keyword.get(config, :conjugation_ttl, :timer.hours(24))

    # Populate ETS cache with DB value
    alias Langler.External.Dictionary.Cache
    Cache.put(table, cache_key, conjugations, ttl: ttl)
  end

  defp conjugation_lookup_lemma(word) do
    lemma = extract_infinitive_lemma(word)

    if lemma do
      String.downcase(lemma)
    else
      nil
    end
  end

  defp definition_fetch_flags(word) do
    defs = word.definitions || []

    %{
      needs_definitions: definitions_stale?(defs),
      needs_pos: is_nil(word.part_of_speech)
    }
  end

  defp needs_definition_fetch?(%{needs_definitions: needs_definitions, needs_pos: needs_pos}) do
    needs_definitions || needs_pos
  end

  defp definition_lookup_term(word) do
    cond do
      is_binary(word.lemma) && String.trim(word.lemma) != "" ->
        String.trim(word.lemma)

      is_binary(word.normalized_form) ->
        String.trim(word.normalized_form)

      true ->
        nil
    end
  end

  defp blank_term?(term), do: is_nil(term) or term == ""

  defp lookup_dictionary_entry(term, language) do
    started_at = System.monotonic_time(:millisecond)
    {:ok, entry} = Dictionary.lookup(term, language: language, target: "en")
    duration = System.monotonic_time(:millisecond) - started_at
    {entry, duration}
  end

  defp build_definition_updates(flags, entry, definitions) do
    updates = %{}

    updates =
      if flags.needs_definitions && definitions != [],
        do: Map.put(updates, :definitions, definitions),
        else: updates

    if flags.needs_pos && entry.part_of_speech,
      do: Map.put(updates, :part_of_speech, entry.part_of_speech),
      else: updates
  end

  defp apply_word_updates(item, word, updates) do
    if map_size(updates) == 0 do
      {:ok, item}
    else
      case word |> Word.changeset(updates) |> Repo.update() do
        {:ok, updated_word} ->
          Logger.debug(
            "StudyLive: stored updates for word_id=#{word.id}: #{inspect(Map.keys(updates))}"
          )

          {:ok, %{item | word: updated_word}}

        {:error, reason} ->
          Logger.warning(
            "StudyLive: failed to store updates for word_id=#{word.id}: #{inspect(reason)}"
          )

          {:ok, item}
      end
    end
  end

  defp definitions_stale?(defs) do
    defs == [] ||
      Enum.all?(defs, fn defn ->
        normalized =
          defn
          |> to_string()
          |> String.downcase()
          |> String.trim()

        normalized == "" ||
          String.starts_with?(normalized, "plural of ") ||
          String.starts_with?(normalized, "feminine") ||
          String.starts_with?(normalized, "masculine") ||
          String.starts_with?(normalized, "present participle") ||
          String.starts_with?(normalized, "past participle") ||
          String.starts_with?(normalized, "gerund of")
      end)
  end

  defp find_item(items, item_id) do
    case Integer.parse(to_string(item_id)) do
      {id, ""} ->
        case Enum.find(items, &(&1.id == id)) do
          nil -> {:error, :not_found}
          item -> {:ok, item}
        end

      _ ->
        {:error, :invalid_id}
    end
  end

  defp format_decimal(nil), do: "0.0×"
  defp format_decimal(value), do: "#{Float.round(value, 2)}×"

  defp interval_label(nil), do: "New"
  defp interval_label(0), do: "Learning"
  defp interval_label(days), do: "#{days}d"

  defp due_badge_class(due_date) do
    if due_now?(%{due_date: due_date}, DateTime.utc_now()) do
      "badge-error/20 text-error border-error/40"
    else
      "badge-success/20 text-success border-success/40"
    end
  end

  defp due_status_label(due_date) do
    if due_now?(%{due_date: due_date}, DateTime.utc_now()) do
      "Due"
    else
      "Scheduled"
    end
  end

  defp format_due_label(nil), do: "immediately"

  defp format_due_label(due_date) do
    Calendar.strftime(due_date, "%b %d, %Y · %H:%M")
  end

  defp recent_history(nil), do: []
  defp recent_history(history), do: history |> Enum.take(-5)

  defp history_pill_class(score) do
    case score do
      0 -> "bg-error/50"
      1 -> "bg-error/30"
      2 -> "bg-warning/50"
      3 -> "bg-primary/50"
      4 -> "bg-success/60"
      _ -> "bg-base-200"
    end
  end

  defp verb?(nil), do: false
  defp verb?(pos) when is_binary(pos), do: String.downcase(pos) == "verb"
  defp verb?(_), do: false

  defp looks_like_spanish_verb?(word) when is_nil(word), do: false

  defp looks_like_spanish_verb?(word) do
    # Check if lemma/normalized_form ends in verb infinitive endings
    term = word.lemma || word.normalized_form || ""
    term = String.downcase(String.trim(term))
    infinitive_match = String.ends_with?(term, ["ar", "er", "ir"]) && String.length(term) > 2

    # Also check if definitions contain "(verb)" indicator
    definitions_contain_verb =
      word.definitions
      |> List.wrap()
      |> Enum.any?(fn def ->
        def
        |> String.downcase()
        |> String.contains?(["(verb)", "verb)", "( verb"])
      end)

    infinitive_match || definitions_contain_verb
  end

  defp find_item_by_word_id(items, word_id) do
    case Enum.find(items, fn item -> item.word && item.word.id == word_id end) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp extract_infinitive_lemma(word) do
    lemma = word.lemma || word.normalized_form || ""
    lemma_trimmed = String.trim(lemma)
    lemma_lower = String.downcase(lemma_trimmed)

    if infinitive_form?(lemma_lower) do
      lemma_trimmed
    else
      extract_infinitive_from_definitions(word.definitions) || lemma_trimmed
    end
  end

  defp infinitive_form?(lemma_lower) do
    String.ends_with?(lemma_lower, ["ar", "er", "ir"]) && String.length(lemma_lower) > 2
  end

  defp extract_infinitive_from_definitions(definitions) do
    definitions
    |> List.wrap()
    |> Enum.find_value(&extract_infinitive_from_definition/1)
  end

  defp extract_infinitive_from_definition(def) do
    extract_verb_infinitive(def) || extract_dash_infinitive(def)
  end

  defp extract_verb_infinitive(def) do
    # Use Unicode-aware pattern to match Spanish characters like ñ
    case Regex.run(~r/\(verb\)\s*[—–-]\s*([\p{L}\p{M}]+)/u, def) do
      [_, infinitive] -> String.trim(infinitive)
      _ -> nil
    end
  end

  defp extract_dash_infinitive(def) do
    # Use Unicode-aware pattern to match Spanish characters like ñ
    case Regex.run(~r/[—–-]\s*([\p{L}\p{M}]+)/u, def) do
      [_, possible_infinitive] -> validate_infinitive(possible_infinitive)
      _ -> nil
    end
  end

  defp validate_infinitive(possible_infinitive) do
    possible_lower = String.downcase(String.trim(possible_infinitive))

    if infinitive_form?(possible_lower) do
      String.trim(possible_infinitive)
    else
      nil
    end
  end

  defp maybe_start_definition_fetch(socket, item_id, flipped_state, item) do
    if flipped_state && item.word do
      maybe_start_definition_fetch_checked(socket, item_id, item)
    else
      socket
    end
  end

  defp maybe_start_definition_fetch_checked(socket, item_id, item) do
    flags = definition_fetch_flags(item.word)

    if needs_definition_fetch?(flags) do
      term = definition_lookup_term(item.word)

      if blank_term?(term) do
        socket
      else
        start_definition_fetch_async(socket, item_id, item)
      end
    else
      socket
    end
  end

  defp start_definition_fetch_async(socket, item_id, item) do
    flags = definition_fetch_flags(item.word)
    term = definition_lookup_term(item.word)

    socket
    |> assign(
      :definitions_loading,
      MapSet.put(socket.assigns[:definitions_loading] || MapSet.new(), item_id)
    )
    |> start_async({:fetch_definitions, item_id}, fn ->
      {entry, _duration} = lookup_dictionary_entry(term, item.word.language)
      {item_id, entry, item.word, flags}
    end)
  end

  defp maybe_start_conjugation_fetch(socket, word_id, expanded_state, item) when is_boolean(expanded_state) do
    cond do
      not expanded_state ->
        socket

      not (item.word && missing_conjugations?(item.word)) ->
        socket

      is_nil(conjugation_lookup_lemma(item.word)) ->
        socket

      true ->
        start_conjugation_fetch_async(socket, word_id, item)
    end
  end

  defp start_conjugation_fetch_async(socket, word_id, item) do
    lookup_lemma = conjugation_lookup_lemma(item.word)

    socket
    |> assign(
      :conjugations_loading,
      MapSet.put(socket.assigns[:conjugations_loading] || MapSet.new(), word_id)
    )
    |> start_async({:fetch_conjugations, word_id}, fn ->
      fetch_conjugations_with_timeout(item.word, lookup_lemma, word_id)
    end)
  end

  defp fetch_conjugations_with_timeout(word, lookup_lemma, word_id) do
    # Refresh word from DB to get latest conjugations
    refreshed_word =
      if word && word.id do
        Vocabulary.get_word(word.id) || word
      else
        word
      end

    # Use Task with timeout to prevent hanging
    task = Task.async(fn -> fetch_conjugations_with_cache(refreshed_word, lookup_lemma) end)

    case Task.yield(task, 30_000) || Task.shutdown(task) do
      {:ok, result} -> result
      nil ->
        Logger.warning("StudyLive: timeout fetching conjugations for word_id=#{word_id}")
        {:error, :timeout}
      {:exit, reason} ->
        Logger.warning("StudyLive: task exited while fetching conjugations for word_id=#{word_id}: #{inspect(reason)}")
        {:error, :exit}
    end
  end

  defp handle_conjugations_success(socket, word_id, conjugations) do
    case find_item_by_word_id(socket.assigns.all_items, word_id) do
      {:ok, item} ->
        if item.word.conjugations != conjugations do
          handle_conjugations_update(socket, word_id, item, conjugations)
        else
          handle_conjugations_no_change(socket, word_id, item)
        end

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp handle_conjugations_update(socket, word_id, item, conjugations) do
    case Vocabulary.update_word_conjugations(item.word, conjugations) do
      {:ok, updated_word} ->
        updated_item = %{item | word: updated_word}
        updated_items = replace_item(socket.assigns.all_items, updated_item)
        dom_id = "items-#{updated_item.id}"

        {:noreply,
         socket
         |> assign(:all_items, updated_items)
         |> clear_conjugations_loading(word_id)
         |> stream_insert(:items, updated_item, dom_id: dom_id)}

      {:error, reason} ->
        Logger.warning(
          "StudyLive: failed to store conjugations for word_id=#{word_id}: #{inspect(reason)}"
        )

        {:noreply, clear_conjugations_loading(socket, word_id)}
    end
  end

  defp handle_conjugations_no_change(socket, word_id, item) do
    updated_items = replace_item(socket.assigns.all_items, item)
    dom_id = "items-#{item.id}"

    {:noreply,
     socket
     |> assign(:all_items, updated_items)
     |> clear_conjugations_loading(word_id)
     |> stream_insert(:items, item, dom_id: dom_id)}
  end

  defp clear_conjugations_loading(socket, word_id) do
    assign(
      socket,
      :conjugations_loading,
      MapSet.delete(socket.assigns[:conjugations_loading] || MapSet.new(), word_id)
    )
  end
end

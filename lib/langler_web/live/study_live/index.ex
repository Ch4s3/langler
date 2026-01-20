defmodule LanglerWeb.StudyLive.Index do
  @moduledoc """
  LiveView for spaced repetition study sessions.
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts
  alias Langler.Content
  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.Wiktionary.Conjugations
  alias Langler.Repo
  alias Langler.Study
  alias Langler.Study.FSRS
  alias Langler.Vocabulary
  alias Langler.Vocabulary.Word
  alias Langler.Vocabulary.Workers.ImportCsvWorker
  alias MapSet
  alias Oban
  alias Phoenix.LiveView.JS
  alias Phoenix.PubSub
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

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    items = Study.list_items_for_user(scope.user.id)
    filter = :now

    # Calculate user level and get recommendations
    user_level = Study.get_user_vocabulary_level(scope.user.id)
    user_id = scope.user.id

    # Load decks and current deck
    decks = Vocabulary.list_decks_for_user(user_id)
    current_deck = Accounts.get_current_deck(user_id)

    # Get user preference for default language
    user_pref = Accounts.get_user_preference(user_id)
    default_language = if user_pref, do: user_pref.target_language, else: "spanish"

    {:ok,
     socket
     |> allow_upload(:csv_file,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> assign(:current_user, scope.user)
     |> assign(:filters, @filters)
     |> assign(:filter, filter)
     |> assign(:search_query, "")
     |> assign(:quality_buttons, @quality_buttons)
     |> assign(:stats, Study.build_study_stats(items))
     |> assign(:all_items, items)
     |> assign(:visible_count, 0)
     |> assign(:flipped_cards, MapSet.new())
     |> assign(:expanded_conjugations, MapSet.new())
     |> assign(:conjugations_loading, MapSet.new())
     |> assign(:definitions_loading, MapSet.new())
     |> assign(:user_level, user_level)
     |> assign(:decks, decks)
     |> assign(:current_deck, current_deck)
     |> assign(:filter_deck_id, nil)
     |> assign(:show_deck_modal, false)
     |> assign(:editing_deck, nil)
     |> assign(:deck_form, to_form(%{"name" => ""}))
     |> assign(:show_csv_import, false)
     |> assign(:csv_import_deck_id, if(current_deck, do: current_deck.id, else: nil))
     |> assign(:csv_preview, nil)
     |> assign(:csv_content, nil)
     |> assign(:csv_importing, false)
     |> assign(:csv_import_job_id, nil)
     |> assign(:default_language, default_language)
     |> subscribe_to_csv_imports(user_id)
     |> assign_async(:recommended_articles, fn ->
       {:ok, %{recommended_articles: Content.get_recommended_articles_for_user(user_id, 5)}}
     end)}
  end

  defp subscribe_to_csv_imports(socket, user_id) do
    # Subscribe to all CSV import notifications for this user
    # The topic pattern is "csv_import:user_id:*" but PubSub doesn't support wildcards
    # So we'll subscribe to a base topic and filter in handle_info
    topic = "csv_import:#{user_id}"
    PubSub.subscribe(Langler.PubSub, topic)
    socket
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = Map.get(params, "q", "") |> String.trim()
    filter = parse_filter_from_params(params, socket.assigns.filter)

    # Only update if different (idempotent - prevents rerenders)
    socket =
      socket
      |> maybe_update_search_query(query)
      |> maybe_update_filter(filter)
      |> refresh_visible_items()

    {:noreply, socket}
  end

  defp maybe_update_search_query(socket, query) do
    if socket.assigns[:search_query] == query do
      socket
    else
      assign(socket, :search_query, query)
    end
  end

  defp maybe_update_filter(socket, filter) do
    if socket.assigns[:filter] == filter do
      socket
    else
      assign(socket, :filter, filter)
    end
  end

  defp parse_filter_from_params(params, default) do
    case params["filter"] do
      "today" -> :today
      "all" -> :all
      "now" -> :now
      _ -> default
    end
  end

  defp refresh_visible_items(socket) do
    visible =
      filter_items(
        socket.assigns.all_items,
        socket.assigns.filter,
        socket.assigns.search_query,
        socket.assigns.filter_deck_id
      )

    socket
    |> assign(:visible_count, length(visible))
    |> stream(:items, visible, reset: true)
  end

  @impl true
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

            <.kpi_cards cards={[
              %{
                title: "Due now",
                value: @stats.due_now,
                meta: "Ready for immediate review",
                value_class: "text-primary"
              },
              %{
                title: "Due today",
                value: @stats.due_today,
                meta: "Includes overdue & later today",
                value_class: "text-secondary"
              },
              %{title: "Total tracked", value: @stats.total, meta: "Words in your study bank"}
            ]} />

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
                navigate={
                  if @filter_deck_id,
                    do: ~p"/study/session?deck_id=#{@filter_deck_id}",
                    else: ~p"/study/session"
                }
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
                  Type a word to narrow results across filters.
                </p>
              </div>
              <.search_input
                id="study-search-input"
                value={@search_query}
                placeholder="Search words…"
                event="search_items"
                clear_event="clear_search"
                debounce={300}
                class="w-full sm:w-96"
              />
            </div>

            <div class="flex flex-col gap-4 rounded-2xl border border-base-200 bg-base-200/30 p-4 sm:flex-row sm:items-center sm:justify-between">
              <div class="space-y-1">
                <p class="text-sm font-semibold text-base-content/80">Filter by deck</p>
                <p class="text-xs text-base-content/60">
                  {if @filter_deck_id do
                    "Showing words from selected deck only"
                  else
                    "Showing words from all decks"
                  end}
                </p>
              </div>
              <div class="flex items-center gap-2">
                <.deck_selector
                  decks={@decks}
                  current_deck={
                    if @filter_deck_id, do: Enum.find(@decks, &(&1.id == @filter_deck_id)), else: nil
                  }
                  event="set_filter_deck"
                  show_all_option={true}
                />
                <button
                  :if={@filter_deck_id}
                  type="button"
                  phx-click="set_filter_deck"
                  phx-value-deck_id=""
                  class="btn btn-sm btn-ghost"
                  title="Show all decks"
                >
                  <.icon name="hero-x-mark" class="h-4 w-4" />
                  <span class="hidden sm:inline">Clear filter</span>
                </button>
                <button
                  type="button"
                  phx-click="show_deck_modal"
                  class="btn btn-sm btn-primary text-white"
                >
                  <.icon name="hero-plus" class="h-4 w-4" />
                  <span class="hidden sm:inline">New deck</span>
                </button>
              </div>
            </div>

            <div class="rounded-2xl border border-base-200 bg-base-200/30 p-4 backdrop-blur sm:p-4 transition-shadow">
              <div class="tabs tabs-boxed bg-transparent p-1 text-sm font-semibold text-base-content/70 overflow-x-auto">
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
        </div>

        <%!-- Recommended Articles Section --%>
        <.recommended_articles_section
          recommended_articles={@recommended_articles}
          filter={@filter}
          user_level={@user_level}
        />

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
            <.list_empty_state
              id="study-empty-state"
              class="hidden only:flex"
            >
              <:title>
                <%= cond do %>
                  <% @search_query != "" -> %>
                    No matches found
                  <% @filter == :now -> %>
                    You're fully caught up
                  <% true -> %>
                    No cards to show
                <% end %>
              </:title>
              <:description>
                <%= cond do %>
                  <% @search_query != "" -> %>
                    Try a different spelling, or clear your search to see everything again.
                  <% @filter == :now -> %>
                    Switch filters or import more words from an article.
                  <% true -> %>
                    Switch filters or import more words from an article.
                <% end %>
              </:description>
              <:actions>
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
              </:actions>
            </.list_empty_state>

            <.study_card
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              item={item}
              flipped={MapSet.member?(@flipped_cards, item.id)}
              definitions_loading={MapSet.member?(@definitions_loading || MapSet.new(), item.id)}
              conjugations_loading={
                if item.word,
                  do: MapSet.member?(@conjugations_loading || MapSet.new(), item.word.id),
                  else: false
              }
              expanded_conjugations={
                if item.word, do: MapSet.member?(@expanded_conjugations, item.word.id), else: false
              }
              quality_buttons={@quality_buttons}
            >
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
            </.study_card>
          </div>
        </div>
      </div>

      <%!-- Deck Management Modal --%>
      <.deck_modal
        show={@show_deck_modal}
        editing_deck={@editing_deck}
        form={@deck_form}
      />

      <%!-- Deck List Section --%>
      <.decks_section decks={@decks} />

      <.csv_import_modal
        show={@show_csv_import}
        decks={@decks}
        csv_import_deck_id={@csv_import_deck_id}
        csv_preview={@csv_preview}
        csv_importing={@csv_importing}
        default_language={@default_language}
        uploads={@uploads}
      />
    </Layouts.app>
    """
  end

  @impl true
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
      stats = Study.build_study_stats(all_items)
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

  def handle_event("search_items", %{"q" => query}, socket) do
    query = String.trim(to_string(query))
    filter_param = filter_to_param(socket.assigns.filter)
    base_path = ~p"/study"

    path =
      cond do
        query != "" && filter_param != "" ->
          ~p"/study?q=#{URI.encode(query)}&filter=#{filter_param}"

        query != "" ->
          ~p"/study?q=#{URI.encode(query)}"

        filter_param != "" ->
          ~p"/study?filter=#{filter_param}"

        true ->
          base_path
      end

    visible = filter_items(socket.assigns.all_items, socket.assigns.filter, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:visible_count, length(visible))
     |> stream(:items, visible, reset: true)
     |> push_patch(to: path, replace: true)}
  end

  def handle_event("clear_search", _params, socket) do
    path = build_study_path("", socket.assigns.filter)

    visible = filter_items(socket.assigns.all_items, socket.assigns.filter, "")

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:visible_count, length(visible))
     |> stream(:items, visible, reset: true)
     |> push_patch(to: path, replace: true)}
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

  ## Deck Management Events

  def handle_event("set_current_deck", %{"deck_id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id

    with_deck_id(deck_id_str, socket, fn deck_id ->
      case Accounts.set_current_deck(user_id, deck_id) do
        {:ok, _pref} ->
          current_deck = Accounts.get_current_deck(user_id)
          decks = Vocabulary.list_decks_for_user(user_id)

          {:noreply,
           socket
           |> assign(:current_deck, current_deck)
           |> assign(:decks, decks)
           |> assign(:filter_deck_id, deck_id)
           |> refresh_visible_items()
           |> put_flash(:info, "Current deck updated")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Unable to set current deck: #{inspect(reason)}")}
      end
    end)
  end

  def handle_event("set_filter_deck", %{"deck_id" => ""}, socket) do
    {:noreply,
     socket
     |> assign(:filter_deck_id, nil)
     |> refresh_visible_items()}
  end

  def handle_event("set_filter_deck", %{"deck_id" => deck_id_str}, socket) do
    with_deck_id(deck_id_str, socket, fn deck_id ->
      {:noreply,
       socket
       |> assign(:filter_deck_id, deck_id)
       |> refresh_visible_items()}
    end)
  end

  def handle_event("show_deck_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_deck_modal, true)
     |> assign(:editing_deck, nil)
     |> assign(:deck_form, to_form(%{"name" => ""}))}
  end

  def handle_event("hide_deck_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_deck_modal, false)
     |> assign(:editing_deck, nil)
     |> assign(:deck_form, to_form(%{"name" => ""}))}
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("validate_deck", %{"name" => name}, socket) do
    form = to_form(%{"name" => name})
    {:noreply, assign(socket, :deck_form, form)}
  end

  def handle_event("create_deck", %{"name" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Deck name cannot be empty")}
    else
      case Vocabulary.create_deck(user_id, %{name: name}) do
        {:ok, _deck} ->
          decks = Vocabulary.list_decks_for_user(user_id)

          {:noreply,
           socket
           |> assign(:decks, decks)
           |> assign(:show_deck_modal, false)
           |> assign(:deck_form, to_form(%{"name" => ""}))
           |> put_flash(:info, "Deck created successfully")}

        {:error, changeset} ->
          errors = translate_errors(changeset)

          {:noreply,
           socket
           |> put_flash(:error, "Unable to create deck: #{errors}")}
      end
    end
  end

  def handle_event("edit_deck", %{"deck_id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id

    with_deck_id(deck_id_str, socket, fn deck_id ->
      case Vocabulary.get_deck_for_user(deck_id, user_id) do
        nil ->
          {:noreply, put_flash(socket, :error, "Deck not found")}

        deck ->
          {:noreply,
           socket
           |> assign(:show_deck_modal, true)
           |> assign(:editing_deck, deck)
           |> assign(:deck_form, to_form(%{"name" => deck.name}))}
      end
    end)
  end

  def handle_event("update_deck", %{"deck_id" => deck_id_str, "name" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id
    name = String.trim(name)

    case Integer.parse(deck_id_str) do
      {deck_id, ""} ->
        if name == "" do
          {:noreply, put_flash(socket, :error, "Deck name cannot be empty")}
        else
          handle_deck_update(socket, deck_id, user_id, name)
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid deck ID")}
    end
  end

  def handle_event("delete_deck", %{"deck_id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id

    with_deck_id(deck_id_str, socket, fn deck_id ->
      case Vocabulary.delete_deck(deck_id, user_id) do
        {:ok, _deck} ->
          decks = Vocabulary.list_decks_for_user(user_id)
          current_deck = Accounts.get_current_deck(user_id)

          {:noreply,
           socket
           |> assign(:decks, decks)
           |> assign(:current_deck, current_deck)
           |> put_flash(:info, "Deck deleted successfully")}

        {:error, :cannot_delete_default} ->
          {:noreply, put_flash(socket, :error, "Cannot delete the default deck")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Unable to delete deck: #{inspect(reason)}")}
      end
    end)
  end

  ## CSV Import Events

  def handle_event("show_csv_import", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_csv_import, true)
     |> assign(:csv_preview, nil)
     |> assign(
       :csv_import_deck_id,
       if(socket.assigns.current_deck, do: socket.assigns.current_deck.id, else: nil)
     )}
  end

  def handle_event("hide_csv_import", _params, socket) do
    {entries, _errors} = uploaded_entries(socket, :csv_file)

    socket =
      Enum.reduce(entries, socket, fn entry, acc -> cancel_upload(acc, :csv_file, entry.ref) end)

    {:noreply,
     socket
     |> assign(:show_csv_import, false)
     |> assign(:csv_preview, nil)
     |> assign(:csv_content, nil)}
  end

  def handle_event("validate_csv_deck", %{"deck_id" => deck_id_str}, socket) do
    deck_id = if deck_id_str != "", do: String.to_integer(deck_id_str), else: nil
    {:noreply, assign(socket, :csv_import_deck_id, deck_id)}
  end

  def handle_event("validate_csv_file", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("parse_csv", _params, socket) do
    # consume_uploaded_entries returns a list of callback return values
    uploaded_files =
      consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
        File.read!(path)
      end)

    case uploaded_files do
      [content] when is_binary(content) ->
        handle_csv_preview(socket, content)

      [] ->
        {:noreply, put_flash(socket, :error, "Please select a CSV file")}

      results when is_list(results) and results != [] ->
        # Handle any list format - extract content from first result
        content = List.first(results)
        handle_csv_preview(socket, content)

      other ->
        # Catch-all for unexpected formats
        Logger.error("Unexpected upload format in parse_csv: #{inspect(other)}")
        {:noreply, put_flash(socket, :error, "Unexpected upload format. Please try again.")}
    end
  end

  def handle_event("import_csv", %{"deck_id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id
    default_language = socket.assigns.default_language

    with_deck_id(deck_id_str, socket, fn deck_id ->
      content = socket.assigns[:csv_content]

      if is_nil(content) do
        {:noreply,
         put_flash(socket, :error, "No CSV file to import. Please upload a file first.")}
      else
        handle_csv_import_with_content(socket, deck_id, user_id, default_language, content)
      end
    end)
  end

  defp handle_csv_import_with_content(socket, deck_id, user_id, default_language, content) do
    # Get deck name for completion message
    deck = Enum.find(socket.assigns.decks, &(&1.id == deck_id))
    deck_name = if deck, do: deck.name, else: "deck"

    # Generate unique job ID for tracking
    job_id = System.unique_integer([:positive, :monotonic])

    # Enqueue the background job
    args = %{
      "csv_content" => content,
      "deck_id" => deck_id,
      "user_id" => user_id,
      "default_language" => default_language,
      "job_id" => job_id,
      "deck_name" => deck_name
    }

    handle_csv_job_insertion(socket, args, job_id)
  end

  defp handle_csv_job_insertion(socket, args, job_id) do
    args
    |> ImportCsvWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:csv_import_job_id, job_id)
         |> assign(:show_csv_import, false)
         |> assign(:csv_preview, nil)
         |> assign(:csv_content, nil)
         |> put_flash(:info, "Cards are being built. You'll be notified when complete.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to start import: #{inspect(reason)}")}
    end
  end

  defp handle_deck_update(socket, deck_id, user_id, name) do
    case Vocabulary.update_deck(deck_id, user_id, %{name: name}) do
      {:ok, _deck} ->
        decks = Vocabulary.list_decks_for_user(user_id)
        current_deck = Accounts.get_current_deck(user_id)

        {:noreply,
         socket
         |> assign(:decks, decks)
         |> assign(:current_deck, current_deck)
         |> assign(:filter_deck_id, nil)
         |> assign(:show_deck_modal, false)
         |> assign(:editing_deck, nil)
         |> assign(:deck_form, to_form(%{"name" => ""}))
         |> put_flash(:info, "Deck updated successfully")}

      {:error, changeset} ->
        errors = translate_errors(changeset)

        {:noreply,
         socket
         |> put_flash(:error, "Unable to update deck: #{errors}")}
    end
  end

  @impl true
  def handle_info({:csv_import_complete, job_id, {:ok, %{message: message}}}, socket) do
    # Only process if this is the job we're waiting for
    if socket.assigns.csv_import_job_id == job_id do
      user_id = socket.assigns.current_scope.user.id
      decks = Vocabulary.list_decks_for_user(user_id)
      items = Study.list_items_for_user(user_id)

      {:noreply,
       socket
       |> assign(:decks, decks)
       |> assign(:all_items, items)
       |> assign(:csv_import_job_id, nil)
       |> refresh_visible_items()
       |> put_flash(:info, message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:csv_import_complete, job_id, {:error, error_message}}, socket) do
    # Only process if this is the job we're waiting for
    if socket.assigns.csv_import_job_id == job_id do
      {:noreply,
       socket
       |> assign(:csv_import_job_id, nil)
       |> put_flash(:error, error_message)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp handle_csv_preview(socket, content) when is_binary(content) do
    {:ok, preview_rows} = parse_csv_preview(content)

    {:noreply,
     socket
     |> assign(:csv_preview, preview_rows)
     |> assign(:csv_content, content)}
  end

  defp handle_csv_preview(socket, {:ok, content}) when is_binary(content) do
    handle_csv_preview(socket, content)
  end

  defp handle_csv_preview(socket, {:error, reason}) do
    {:noreply, put_flash(socket, :error, "Failed to read file: #{inspect(reason)}")}
  end

  defp parse_csv_preview(content) do
    rows =
      content
      |> String.trim()
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(10)
      |> Enum.map(fn line ->
        case String.split(line, ",") do
          [word] ->
            {String.trim(word), nil}

          [word, language] ->
            {String.trim(word), String.trim(language)}

          parts when length(parts) > 2 ->
            [word, language | _] = parts
            {String.trim(word), String.trim(language)}
        end
      end)

    {:ok, rows}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
  end

  defp parse_deck_id(deck_id_str) do
    case Integer.parse(to_string(deck_id_str)) do
      {deck_id, ""} -> {:ok, deck_id}
      _ -> {:error, :invalid_deck_id}
    end
  end

  defp with_deck_id(deck_id_str, socket, fun) do
    case parse_deck_id(deck_id_str) do
      {:ok, deck_id} -> fun.(deck_id)
      {:error, _} -> {:noreply, put_flash(socket, :error, "Invalid deck ID")}
    end
  end

  defp filter_to_param(:now), do: "now"
  defp filter_to_param(:today), do: "today"
  defp filter_to_param(:all), do: "all"
  defp filter_to_param(_), do: ""

  defp filter_label(filter) do
    Enum.find_value(@filters, "All words", fn %{id: id, label: label} ->
      if id == filter, do: label
    end)
  end

  @impl true
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
        {:noreply, remove_loading(socket, :definitions_loading, item_id)}
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
    Logger.debug(
      "StudyLive: handle_async received conjugations for word_id=#{word_id}: #{inspect(conjugations_map)}"
    )

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

    {:noreply, remove_loading(socket, :conjugations_loading, word_id)}
  end

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

  defp filter_items(items, filter, query, filter_deck_id \\ nil) do
    now = DateTime.utc_now()
    end_of_day = Study.end_of_day(now)
    downcased_query = String.downcase(query || "")

    Enum.filter(items, fn item ->
      matches_filter?(item, filter, now, end_of_day) and
        matches_query?(item.word, downcased_query) and
        matches_deck?(item, filter_deck_id)
    end)
  end

  defp matches_filter?(item, filter, now, end_of_day) do
    case filter do
      :now -> Study.due_now?(item, now)
      :today -> Study.due_today?(item, end_of_day)
      :all -> true
    end
  end

  defp matches_query?(_word, query) when query == "", do: true
  defp matches_query?(word, query), do: match_query?(word, query)

  defp matches_deck?(_item, nil), do: true

  defp matches_deck?(item, filter_deck_id) do
    word_id = item.word.id
    Repo.get_by(Langler.Vocabulary.DeckWord, deck_id: filter_deck_id, word_id: word_id) != nil
  end

  defp match_query?(%Word{} = word, query) do
    lemma = word.lemma || ""
    normalized = word.normalized_form || ""

    String.contains?(String.downcase(lemma), query) or
      String.contains?(String.downcase(normalized), query)
  end

  defp match_query?(_, _), do: false

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
      Logger.debug(
        "StudyLive: fetching conjugations from external for word_id=#{word.id}, lemma=#{lookup_lemma}"
      )

      case Conjugations.fetch_conjugations(lookup_lemma, word.language) do
        {:ok, conjugations_map} ->
          Logger.debug("StudyLive: successfully fetched conjugations for word_id=#{word.id}")
          conjugations_map

        {:error, reason} ->
          Logger.warning(
            "StudyLive: failed to fetch conjugations for word_id=#{word.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  rescue
    e ->
      Logger.error(
        "StudyLive: exception fetching conjugations for word_id=#{word.id}: #{inspect(e)}"
      )

      {:error, :exception}
  catch
    :exit, reason ->
      Logger.error(
        "StudyLive: exit while fetching conjugations for word_id=#{word.id}: #{inspect(reason)}"
      )

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

  defp maybe_start_conjugation_fetch(socket, word_id, expanded_state, item)
       when is_boolean(expanded_state) do
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
    |> add_loading(:conjugations_loading, word_id)
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
      {:ok, result} ->
        result

      nil ->
        Logger.warning("StudyLive: timeout fetching conjugations for word_id=#{word_id}")
        {:error, :timeout}

      {:exit, reason} ->
        Logger.warning(
          "StudyLive: task exited while fetching conjugations for word_id=#{word_id}: #{inspect(reason)}"
        )

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
    remove_loading(socket, :conjugations_loading, word_id)
  end

  # Loading state helpers for MapSet-based loading indicators
  defp add_loading(socket, key, id) do
    set = socket.assigns[key] || MapSet.new()
    assign(socket, key, MapSet.put(set, id))
  end

  defp remove_loading(socket, key, id) do
    set = socket.assigns[key] || MapSet.new()
    assign(socket, key, MapSet.delete(set, id))
  end

  # URL building helper for study page with query and filter params
  defp build_study_path(query, filter) do
    base_path = ~p"/study"
    query = String.trim(to_string(query))
    filter_param = if filter, do: filter_to_param(filter), else: ""

    cond do
      query != "" && filter_param != "" ->
        ~p"/study?q=#{URI.encode(query)}&filter=#{filter_param}"

      query != "" ->
        ~p"/study?q=#{URI.encode(query)}"

      filter_param != "" ->
        ~p"/study?filter=#{filter_param}"

      true ->
        base_path
    end
  end
end

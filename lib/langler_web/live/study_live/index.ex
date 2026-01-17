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
    recommended_articles = Content.get_recommended_articles_for_user(scope.user.id, 5)

    {:ok,
     socket
     |> assign(:current_user, scope.user)
     |> assign(:filters, @filters)
     |> assign(:filter, filter)
     |> assign(:search_query, "")
     |> assign(:quality_buttons, @quality_buttons)
     |> assign(:stats, build_stats(items))
     |> assign(:all_items, items)
     |> assign(:flipped_cards, MapSet.new())
     |> assign(:expanded_conjugations, MapSet.new())
     |> assign(:user_level, user_level)
     |> assign(:recommended_articles, recommended_articles)
     |> stream(:items, visible_items)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <div class="card section-card bg-base-100/95">
          <div class="card-body gap-6">
            <div class="section-header">
              <p class="section-header__eyebrow">Study overview</p>
              <h1 class="section-header__title">Stay consistent with your deck</h1>
              <p class="section-header__lede">
                Track upcoming reviews and keep tabs on due cards with quick filters.
              </p>
            </div>

            <div class="grid gap-4 sm:grid-cols-3">
              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow transition duration-300 hover:-translate-y-1">
                <div class="stat-title text-base-content/60">Due now</div>
                <div class="stat-value text-4xl text-primary">{@stats.due_now}</div>
                <div class="stat-desc text-base-content/70">Ready for immediate review</div>
              </div>

              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow transition duration-300 hover:-translate-y-1">
                <div class="stat-title text-base-content/60">Due today</div>
                <div class="stat-value text-4xl text-secondary">{@stats.due_today}</div>
                <div class="stat-desc text-base-content/70">
                  Includes overdue &amp; later today
                </div>
              </div>

              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow transition duration-300 hover:-translate-y-1">
                <div class="stat-title text-base-content/60">Total tracked</div>
                <div class="stat-value text-4xl text-base-content">{@stats.total}</div>
                <div class="stat-desc text-base-content/70">Words in your study bank</div>
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
                navigate={~p"/articles"}
                class="btn btn-sm btn-primary text-white shadow transition hover:-translate-y-0.5"
              >
                Go to library
              </.link>
              <.link
                navigate={~p"/articles/new"}
                class="btn btn-sm btn-ghost border border-dashed border-base-300"
              >
                Import article
              </.link>
            </div>

            <div class="flex flex-col gap-3 rounded-2xl border border-base-200 bg-base-50/70 p-4 sm:flex-row sm:items-center sm:justify-between">
              <p class="text-sm font-semibold text-base-content/70">Search your deck</p>
              <form phx-change="search_items" class="w-full sm:w-auto">
                <label class="input input-bordered flex items-center gap-2 w-full sm:w-80">
                  <.icon name="hero-magnifying-glass" class="h-4 w-4 text-base-content/60" />
                  <input
                    type="text"
                    name="search_query"
                    value={@search_query}
                    placeholder="Search words..."
                    phx-debounce="300"
                    autocomplete="off"
                    class="grow"
                  />
                </label>
              </form>
            </div>

            <div class="tabs tabs-boxed bg-base-200/70 p-1 text-sm font-semibold text-base-content/70">
              <button
                :for={filter <- @filters}
                type="button"
                class={[
                  "tab tab-lg rounded-xl transition",
                  @filter == filter.id && "tab-active bg-base-100 text-base-content shadow"
                ]}
                phx-click="set_filter"
                phx-value-filter={filter.id}
              >
                {filter.label}
              </button>
            </div>

            <%!-- Recommended Articles Section --%>
            <div
              :if={@recommended_articles != [] && @filter == :now}
              class="card section-card bg-base-100/95"
            >
              <div class="card-body">
                <h2 class="card-title">
                  <.icon name="hero-light-bulb" class="h-6 w-6 text-primary" /> Recommended Reading
                  <span class="badge badge-primary badge-sm">
                    {@user_level.cefr_level || "Learning"}
                  </span>
                </h2>
                <p class="text-sm text-base-content/70">
                  Articles matched to your vocabulary level
                </p>

                <div class="space-y-3 mt-4">
                  <div
                    :for={rec <- @recommended_articles}
                    class="flex items-start gap-3 p-3 rounded-lg bg-base-200/50
                              hover:bg-base-200 transition"
                  >
                    <div class="flex-1">
                      <.link
                        href={rec.article.url}
                        target="_blank"
                        class="font-semibold hover:text-primary"
                      >
                        {rec.article.title}
                      </.link>
                      <button
                        phx-click="import_article"
                        phx-value-id={rec.article.id}
                        class="btn btn-xs btn-primary ml-2"
                      >
                        Import
                      </button>
                      <div class="flex gap-2 mt-1">
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
                      <div class="text-xs text-base-content/60">Match</div>
                      <div class="text-lg font-semibold text-primary">
                        {trunc(rec.score * 100)}%
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
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
              <p class="text-lg font-semibold">You're fully caught up</p>
              <p class="text-sm">Switch filters or import more words from an article.</p>
              <.link
                navigate={~p"/articles"}
                class="mt-4 btn btn-sm btn-primary text-white"
              >
                Explore library
              </.link>
            </div>

            <div
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              class="card border border-base-200 bg-base-100/95 shadow-xl backdrop-blur transition duration-300 hover:-translate-y-1"
            >
              <div class="card-body gap-5">
                <button
                  type="button"
                  phx-click="toggle_card"
                  phx-value-id={item.id}
                  phx-hook="WordCardToggle"
                  id={"study-card-#{item.id}"}
                  data-item-id={item.id}
                  class="group relative w-full rounded-2xl border border-dashed border-base-200 bg-base-100/80 p-4 text-left transition duration-300 hover:border-primary/40 focus-visible:ring focus-visible:ring-primary/40"
                >
                  <% flipped = MapSet.member?(@flipped_cards, item.id) %>
                  <% definitions = item.word && (item.word.definitions || []) %>
                  <div class="relative" style="min-height: 16rem;">
                    <div class={[
                      "space-y-4 transition-opacity duration-300",
                      flipped && "opacity-0 pointer-events-none absolute inset-0"
                    ]}>
                      <div class="flex flex-wrap items-start justify-between gap-4">
                        <div class="flex flex-col gap-1">
                          <p
                            class="inline-flex items-center gap-2 text-3xl font-semibold text-base-content cursor-pointer transition hover:text-primary"
                            phx-hook="CopyToClipboard"
                            data-copy-text={
                              item.word && (item.word.lemma || item.word.normalized_form)
                            }
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
                      "absolute inset-0 flex h-full flex-col gap-4 rounded-xl border border-primary/30 bg-primary/5 p-4 text-base-content transition-opacity duration-300",
                      flipped && "opacity-100",
                      !flipped && "opacity-0 pointer-events-none"
                    ]}>
                      <p class="text-sm font-semibold uppercase tracking-widest text-primary/70">
                        Definition
                      </p>
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
                      <p class="text-xs text-base-content/60">Tap again to return.</p>
                    </div>
                  </div>
                </button>

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
                      class="btn btn-sm btn-primary/80 text-white hover:brightness-110"
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
                    class="mt-4 rounded-xl border border-base-200 bg-base-100/90 p-4 shadow-inner"
                  >
                    {render_conjugation_table(assigns, item.word.conjugations)}
                  </div>
                </div>

                <div class="flex flex-col gap-2">
                  <p class="text-xs font-semibold uppercase tracking-widest text-base-content/60">
                    Rate this card
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={button <- @quality_buttons}
                      type="button"
                      class={[
                        "btn btn-sm font-semibold text-white transition duration-200 hover:-translate-y-0.5 hover:shadow-lg focus-visible:ring focus-visible:ring-offset-2 focus-visible:ring-primary/40",
                        button.class
                      ]}
                      phx-click="rate_word"
                      phx-value-item-id={item.id}
                      phx-value-quality={button.score}
                    >
                      {button.label}
                    </button>
                  </div>
                </div>
              </div>
            </div>
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

      recommended_articles =
        Content.get_recommended_articles_for_user(socket.assigns.current_user.id, 5)

      {:noreply,
       socket
       |> assign(:user_level, user_level)
       |> assign(:recommended_articles, recommended_articles)
       |> put_flash(:info, "Article imported successfully")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Failed to import article")}
    end
  end

  def handle_event("toggle_card", %{"id" => id}, socket) do
    with {item_id, ""} <- Integer.parse(to_string(id)),
         {:ok, item} <- find_item(socket.assigns.all_items, item_id),
         {:ok, ensured_item} <- ensure_word_definitions(item) do
      flipped = toggle_set_member(socket.assigns.flipped_cards, item_id)

      updated_items = replace_item(socket.assigns.all_items, ensured_item)
      flipped_state = MapSet.member?(flipped, item_id)

      dom_id = "items-#{item_id}"

      {:noreply,
       socket
       |> assign(:all_items, updated_items)
       |> assign(:flipped_cards, flipped)
       |> stream_insert(:items, ensured_item, dom_id: dom_id)
       |> push_event("study:card-toggled", %{id: item_id, flipped: flipped_state})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_conjugations", %{"word-id" => word_id_str}, socket) do
    case fetch_conjugation_item(socket.assigns.all_items, word_id_str) do
      {:ok, word_id, item} ->
        updated_item = maybe_update_conjugations(item)
        expanded = toggle_set_member(socket.assigns.expanded_conjugations, word_id)
        updated_items = replace_item(socket.assigns.all_items, updated_item)
        dom_id = "items-#{updated_item.id}"

        {:noreply,
         socket
         |> assign(:all_items, updated_items)
         |> assign(:expanded_conjugations, expanded)
         |> stream_insert(:items, updated_item, dom_id: dom_id)}

      :error ->
        {:noreply, socket}
    end
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

  defp maybe_update_conjugations(%{word: nil} = item), do: item

  defp maybe_update_conjugations(%{word: word} = item) do
    if missing_conjugations?(word) do
      update_conjugations(item, word)
    else
      item
    end
  end

  defp missing_conjugations?(word) do
    is_nil(word.conjugations) or word.conjugations == %{}
  end

  defp update_conjugations(item, word) do
    lookup_lemma = conjugation_lookup_lemma(word)

    if lookup_lemma do
      case fetch_and_store_conjugations(word, lookup_lemma) do
        {:ok, updated_word} ->
          %{item | word: updated_word}

        {:error, :store, reason} ->
          Logger.warning(
            "StudyLive: failed to store conjugations for word_id=#{word.id}: #{inspect(reason)}"
          )

          item

        {:error, :fetch, reason} ->
          Logger.warning(
            "StudyLive: failed to fetch conjugations for #{lookup_lemma}: #{inspect(reason)}"
          )

          item
      end
    else
      item
    end
  end

  defp fetch_and_store_conjugations(word, lookup_lemma) do
    case Conjugations.fetch_conjugations(lookup_lemma, word.language) do
      {:ok, conjugations_map} ->
        case Vocabulary.update_word_conjugations(word, conjugations_map) do
          {:ok, updated_word} ->
            Logger.debug("StudyLive: stored conjugations for word_id=#{word.id}")
            {:ok, updated_word}

          {:error, reason} ->
            {:error, :store, reason}
        end

      {:error, reason} ->
        {:error, :fetch, reason}
    end
  end

  defp conjugation_lookup_lemma(word) do
    lemma = extract_infinitive_lemma(word)

    if lemma do
      String.downcase(lemma)
    else
      nil
    end
  end

  defp ensure_word_definitions(%{word: nil} = item), do: {:ok, item}

  @dialyzer {:nowarn_function, ensure_word_definitions: 1}
  defp ensure_word_definitions(%{word: word} = item) do
    flags = definition_fetch_flags(word)

    if needs_definition_fetch?(flags) do
      maybe_fetch_and_update_definitions(item, word, flags)
    else
      {:ok, item}
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

  defp maybe_fetch_and_update_definitions(item, word, flags) do
    term = definition_lookup_term(word)

    if blank_term?(term) do
      Logger.debug("StudyLive: skipping definition fetch for word #{word.id} (blank term)")
      {:ok, item}
    else
      Logger.debug(
        "StudyLive: fetching definitions for #{inspect(term)} (word_id=#{word.id}) needs_defs=#{flags.needs_definitions} needs_pos=#{flags.needs_pos}"
      )

      {entry, duration} = lookup_dictionary_entry(term, word.language)

      Logger.debug(
        "StudyLive: dictionary lookup complete word_id=#{word.id} defs=#{length(entry.definitions || [])} pos=#{inspect(entry.part_of_speech)} duration_ms=#{duration}"
      )

      updates = build_definition_updates(flags, entry)
      apply_word_updates(item, word, updates)
    end
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

  defp build_definition_updates(flags, entry) do
    updates = %{}

    updates =
      if flags.needs_definitions && (entry.definitions || []) != [],
        do: Map.put(updates, :definitions, entry.definitions),
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

  defp render_conjugation_table(assigns, nil) do
    assigns = assign(assigns, :conjugations, nil)

    ~H"""
    <p class="text-sm text-base-content/70">Loading conjugations...</p>
    """
  end

  defp render_conjugation_table(assigns, %{} = conjugations) when map_size(conjugations) == 0 do
    assigns = assign(assigns, :conjugations, conjugations)

    ~H"""
    <p class="text-sm text-base-content/70">Conjugations not available for this verb.</p>
    """
  end

  defp render_conjugation_table(assigns, conjugations) when is_map(conjugations) do
    assigns = assign(assigns, :conjugations, conjugations)

    ~H"""
    <div class="space-y-6">
      <h3 class="text-lg font-semibold text-base-content">Conjugations</h3>

      <%= if Map.has_key?(@conjugations, "indicative") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Indicative</h4>
          {render_mood(assigns, @conjugations["indicative"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "subjunctive") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Subjunctive</h4>
          {render_mood(assigns, @conjugations["subjunctive"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "imperative") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Imperative</h4>
          {render_mood(assigns, @conjugations["imperative"])}
        </div>
      <% end %>

      <%= if Map.has_key?(@conjugations, "non_finite") do %>
        <div class="space-y-3">
          <h4 class="text-md font-semibold text-base-content/80">Non-finite Forms</h4>
          <div class="grid grid-cols-3 gap-2 text-sm">
            <%= if Map.has_key?(@conjugations["non_finite"], "infinitive") do %>
              <div>
                <span class="font-semibold text-base-content/70">Infinitive:</span>
                <span class="ml-2">{@conjugations["non_finite"]["infinitive"]}</span>
              </div>
            <% end %>
            <%= if Map.has_key?(@conjugations["non_finite"], "gerund") do %>
              <div>
                <span class="font-semibold text-base-content/70">Gerund:</span>
                <span class="ml-2">{@conjugations["non_finite"]["gerund"]}</span>
              </div>
            <% end %>
            <%= if Map.has_key?(@conjugations["non_finite"], "past_participle") do %>
              <div>
                <span class="font-semibold text-base-content/70">Past Participle:</span>
                <span class="ml-2">{@conjugations["non_finite"]["past_participle"]}</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_mood(assigns, mood_conjugations) when is_map(mood_conjugations) do
    assigns = assign(assigns, :mood_conjugations, mood_conjugations)

    ~H"""
    <div class="space-y-4">
      <%= for {tense, forms} <- @mood_conjugations do %>
        <div class="space-y-2">
          <h5 class="text-sm font-semibold text-base-content/70 capitalize">{tense}</h5>
          {render_two_column_conjugations(forms)}
        </div>
      <% end %>
    </div>
    """
  end

  defp render_mood(assigns, _) do
    ~H"""
    <p class="text-sm text-base-content/70">No conjugations available.</p>
    """
  end

  defp render_two_column_conjugations(forms) do
    assigns = %{forms: forms}

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-sm whitespace-normal conjugation-table">
        <tbody>
          <tr class="bg-base-200/60 text-xs uppercase tracking-widest text-base-content/60">
            <th class="w-32">Singular</th>
            <th>Conjugation</th>
            <th class="w-32">Plural</th>
            <th>Conjugation</th>
          </tr>
          <%= for row <- conjugation_rows(@forms) do %>
            <tr class="align-top">
              <td class={["conjugation-person", "pair-left"]}>{row.left.person}</td>
              <td class={["conjugation-form", "pair-left"]}>{row.left.form}</td>
              <td class={["conjugation-person", "pair-right"]}>{row.right.person}</td>
              <td class={["conjugation-form", "pair-right"]}>{row.right.form}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp conjugation_rows(forms) do
    singular = [
      {"yo", Map.get(forms, "yo")},
      {"tú", Map.get(forms, "tú")},
      {"él/ella/usted", Map.get(forms, "él/ella/usted")}
    ]

    plural = [
      {"nosotros/nosotras", Map.get(forms, "nosotros/nosotras")},
      {"vosotros/vosotras", Map.get(forms, "vosotros/vosotras")},
      {"ellos/ellas/ustedes", Map.get(forms, "ellos/ellas/ustedes")}
    ]

    singular
    |> Enum.zip(plural)
    |> Enum.map(fn {{s_person, s_form}, {p_person, p_form}} ->
      %{
        left: %{person: s_person, form: s_form || "—"},
        right: %{person: p_person, form: p_form || "—"}
      }
    end)
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
    case Regex.run(~r/\(verb\)\s*[—–-]\s*(\w+)/i, def) do
      [_, infinitive] -> String.trim(infinitive)
      _ -> nil
    end
  end

  defp extract_dash_infinitive(def) do
    case Regex.run(~r/[—–-]\s*(\w+)/i, def) do
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
end

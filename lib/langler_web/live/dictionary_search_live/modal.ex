defmodule LanglerWeb.DictionarySearchLive.Modal do
  @moduledoc """
  LiveComponent for global dictionary search modal.
  Accessible via Cmd+J keyboard shortcut from anywhere in the app.
  """
  use LanglerWeb, :live_component

  alias Langler.Accounts
  alias Langler.Accounts.GoogleTranslateConfig
  alias Langler.External.Dictionary
  alias Langler.External.Dictionary.Wiktionary.Conjugations
  alias Langler.Study
  alias Langler.Vocabulary

  require Logger

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:result, fn -> nil end)
      |> assign_new(:conjugations, fn -> nil end)
      |> assign_new(:word_id, fn -> nil end)
      |> assign_new(:already_studying, fn -> false end)
      |> assign_new(:just_added, fn -> false end)
      |> assign_new(:error, fn -> nil end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="dictionary-search-modal-wrapper"
      phx-hook="DictionarySearch"
      phx-target={@myself}
    >
      <dialog
        id="dictionary-search-modal"
        class={[
          "modal modal-middle",
          @open && "modal-open"
        ]}
        open={@open}
        role="dialog"
        aria-modal="true"
        aria-labelledby="dictionary-search-title"
        phx-click-away="close_search"
        phx-target={@myself}
      >
        <div class="modal-box w-full max-w-2xl rounded-2xl bg-base-100/95 backdrop-blur-sm shadow-2xl border border-base-200">
          <%!-- Header with close button --%>
          <div class="flex items-center justify-between gap-3 mb-4">
            <div class="flex items-center gap-2 text-base-content/60">
              <.icon name="hero-book-open" class="h-5 w-5" />
              <h2
                id="dictionary-search-title"
                class="text-sm font-semibold text-base-content tracking-tight"
              >
                Dictionary Search
              </h2>
              <kbd class="kbd kbd-sm">Cmd+J</kbd>
            </div>
            <button
              type="button"
              class="btn btn-circle btn-ghost btn-sm"
              phx-click="close_search"
              phx-target={@myself}
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>

          <%!-- Search form --%>
          <form id="dictionary-search-form" phx-submit="search" phx-target={@myself}>
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-4 top-1/2 -translate-y-1/2 h-5 w-5 text-base-content/40"
              />
              <.input
                type="text"
                name="query"
                value={@query}
                placeholder="Search for a word..."
                class={
                  "input input-lg input-bordered w-full rounded-xl focus:input-primary pl-12 " <>
                    if(@query != "", do: "pr-20", else: "pr-16")
                }
                autocomplete="off"
                id="dictionary-search-input"
              />
              <button
                :if={@query != ""}
                type="button"
                class="absolute right-11 top-1/2 -translate-y-1/2 btn btn-circle btn-ghost btn-xs z-10"
                phx-click="clear_query"
                phx-target={@myself}
              >
                <.icon name="hero-x-mark" class="h-4 w-4" />
              </button>
              <kbd class="absolute right-3 top-1/2 -translate-y-1/2 kbd kbd-sm pointer-events-none text-base-content/70 z-20 bg-base-200/80">
                ⏎
              </kbd>
            </div>
          </form>

          <%!-- Loading state --%>
          <div :if={@searching} class="mt-6 space-y-4 animate-pulse">
            <div class="h-6 w-32 rounded-full bg-base-300/80" />
            <div class="h-4 w-24 rounded-full bg-base-200" />
            <div class="space-y-2 mt-4">
              <div class="h-3 w-full rounded-full bg-base-200" />
              <div class="h-3 w-5/6 rounded-full bg-base-200" />
              <div class="h-3 w-4/6 rounded-full bg-base-200" />
            </div>
          </div>

          <%!-- Error state --%>
          <div :if={@error} class="alert alert-error mt-4">
            <.icon name="hero-exclamation-circle" class="h-5 w-5" />
            <span>{@error}</span>
          </div>

          <%!-- Results --%>
          <div :if={@result && !@searching} id="dictionary-result" class="mt-6 space-y-4">
            <%!-- Word header --%>
            <div class="space-y-1">
              <div class="flex items-center gap-3">
                <h3 class="text-2xl font-bold text-base-content">{@result.word}</h3>
                <span
                  :if={@result.translation}
                  class="badge badge-primary badge-lg text-white font-medium"
                >
                  {@result.translation}
                </span>
              </div>
              <div class="flex items-center gap-2 text-sm text-base-content/60">
                <span :if={@result.part_of_speech} class="font-medium uppercase">
                  {@result.part_of_speech}
                </span>
                <span :if={@result.pronunciation}>
                  /{@result.pronunciation}/
                </span>
              </div>
            </div>

            <%!-- Definitions --%>
            <div :if={@result.definitions && @result.definitions != []} class="space-y-2">
              <h4 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
                Definitions
              </h4>
              <ol class="list-decimal pl-5 space-y-1 text-base-content/80">
                <li :for={definition <- @result.definitions} class="leading-relaxed">
                  {definition}
                </li>
              </ol>
            </div>

            <%!-- Conjugations (for verbs) --%>
            <div
              :if={
                (@result.part_of_speech &&
                   String.downcase(@result.part_of_speech) in ["verb", "verbo"]) ||
                  (@result.definitions &&
                     Enum.any?(@result.definitions, fn def ->
                       is_binary(def) && String.contains?(String.downcase(def), "(verb)")
                     end))
              }
              class="space-y-3"
            >
              <details class="collapse collapse-arrow bg-base-200/50 rounded-xl">
                <summary class="collapse-title font-semibold text-sm uppercase tracking-wide">
                  <.icon name="hero-table-cells" class="h-4 w-4 inline mr-1" /> Conjugations
                </summary>
                <div class="collapse-content">
                  <div :if={@conjugations && map_size(@conjugations) > 0}>
                    <.render_conjugations conjugations={@conjugations} />
                  </div>
                  <div
                    :if={!@conjugations || map_size(@conjugations) == 0}
                    class="py-4 text-center text-sm text-base-content/60"
                  >
                    <p>Conjugations could not be loaded for this verb.</p>
                    <a
                      :if={@result.source_url}
                      href={@result.source_url}
                      target="_blank"
                      rel="noopener"
                      class="mt-2 inline-flex items-center gap-1 text-xs text-primary hover:underline"
                    >
                      View on Wiktionary
                      <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
                    </a>
                  </div>
                </div>
              </details>
            </div>

            <%!-- Wiktionary link --%>
            <a
              :if={@result.source_url}
              href={@result.source_url}
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1 text-xs text-base-content/60 hover:text-primary transition-colors"
            >
              View on Wiktionary <.icon name="hero-arrow-top-right-on-square" class="h-3 w-3" />
            </a>

            <%!-- Action buttons --%>
            <div class="pt-4 border-t border-base-200 flex items-center justify-between">
              <div>
                <span
                  :if={@just_added}
                  id="study-added-badge"
                  class="badge badge-success gap-1 text-white"
                >
                  <.icon name="hero-check" class="h-4 w-4" /> Added to Study
                </span>
                <span
                  :if={@already_studying && !@just_added}
                  id="already-studying-badge"
                  class="badge badge-info gap-1"
                >
                  <.icon name="hero-academic-cap" class="h-4 w-4" /> Already Studying
                </span>
              </div>
              <button
                :if={@result && !@already_studying && !@just_added}
                id="add-to-study-btn"
                type="button"
                class="btn btn-primary text-white"
                phx-click="add_to_study"
                phx-target={@myself}
              >
                <.icon name="hero-plus" class="h-5 w-5" /> Add to Study
              </button>
              <.link
                :if={@already_studying || @just_added}
                navigate={~p"/study"}
                class="btn btn-ghost btn-sm"
              >
                Go to Study <.icon name="hero-arrow-right" class="h-4 w-4" />
              </.link>
            </div>
          </div>

          <%!-- Empty state --%>
          <div
            :if={!@result && !@searching && !@error && @query == ""}
            class="mt-6 text-center py-8 text-base-content/50"
          >
            <.icon name="hero-magnifying-glass" class="h-12 w-12 mx-auto mb-3 opacity-50" />
            <p>Type a word to search for its definition</p>
          </div>
        </div>

        <form method="dialog" class="modal-backdrop bg-black/50">
          <button phx-click="close_search" phx-target={@myself}>close</button>
        </form>
      </dialog>
    </div>
    """
  end

  defp render_conjugations(assigns) do
    ~H"""
    <div class="space-y-4 pt-2">
      <div :for={{mood, tenses} <- @conjugations} :if={mood != "non_finite"} class="space-y-2">
        <h5 class="text-xs font-bold uppercase tracking-wider text-base-content/70">
          {humanize_mood(mood)}
        </h5>
        <div :for={{tense, persons} <- tenses} class="space-y-1">
          <p class="text-xs font-medium text-base-content/60">{humanize_tense(tense)}</p>
          <table class="conjugation-table w-full text-sm">
            <tbody>
              <tr :for={row <- conjugation_rows(persons)}>
                <td class="conjugation-person pair-left">{Enum.at(row, 0) |> elem(0)}</td>
                <td class="conjugation-form pair-left">{Enum.at(row, 0) |> elem(1)}</td>
                <td :if={Enum.at(row, 1)} class="conjugation-person pair-right">
                  {Enum.at(row, 1) |> elem(0)}
                </td>
                <td :if={Enum.at(row, 1)} class="conjugation-form pair-right">
                  {Enum.at(row, 1) |> elem(1)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={Map.has_key?(@conjugations, "non_finite")} class="space-y-2">
        <h5 class="text-xs font-bold uppercase tracking-wider text-base-content/70">
          Non-finite Forms
        </h5>
        <div class="flex flex-wrap gap-3">
          <div
            :for={{form, value} <- @conjugations["non_finite"]}
            class="rounded-lg bg-base-300/50 px-3 py-1.5"
          >
            <span class="text-xs text-base-content/60">{humanize_tense(form)}:</span>
            <span class="font-medium ml-1">{value}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp conjugation_rows(persons) when is_map(persons) do
    person_order = [
      "yo",
      "tú",
      "él/ella/usted",
      "nosotros/nosotras",
      "vosotros/vosotras",
      "ellos/ellas/ustedes"
    ]

    person_order
    |> Enum.filter(&Map.has_key?(persons, &1))
    |> Enum.map(&{&1, Map.get(persons, &1, "")})
    |> Enum.chunk_every(2)
  end

  defp conjugation_rows(_), do: []

  defp humanize_mood("indicative"), do: "Indicative"
  defp humanize_mood("subjunctive"), do: "Subjunctive"
  defp humanize_mood("imperative"), do: "Imperative"
  defp humanize_mood(mood), do: String.capitalize(mood)

  defp humanize_tense("present"), do: "Present"
  defp humanize_tense("preterite"), do: "Preterite"
  defp humanize_tense("imperfect"), do: "Imperfect"
  defp humanize_tense("future"), do: "Future"
  defp humanize_tense("conditional"), do: "Conditional"
  defp humanize_tense("infinitive"), do: "Infinitive"
  defp humanize_tense("gerund"), do: "Gerund"
  defp humanize_tense("past_participle"), do: "Past Participle"
  defp humanize_tense(tense), do: String.capitalize(to_string(tense))

  @impl true
  def handle_event("open_search", _params, socket) do
    # Toggle behavior: if already open, close it; otherwise open it
    if socket.assigns.open do
      {:noreply, assign(socket, :open, false)}
    else
      socket =
        socket
        |> assign(:open, true)
        |> push_event("dictionary:focus-input", %{})

      {:noreply, socket}
    end
  end

  def handle_event("close_search", _params, socket) do
    # Just close - preserve all search state
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("clear_query", _params, socket) do
    {:noreply,
     socket
     |> assign(:query, "")
     |> assign(:result, nil)
     |> assign(:conjugations, nil)
     |> assign(:word_id, nil)
     |> assign(:already_studying, false)
     |> assign(:just_added, false)
     |> assign(:error, nil)}
  end

  def handle_event("search", %{"query" => query}, socket) when query in ["", nil] do
    {:noreply, assign(socket, :error, "Please enter a word to search")}
  end

  def handle_event("search", %{"query" => query}, socket) do
    user_id = socket.assigns.current_scope.user.id
    query = String.trim(query)

    socket =
      socket
      |> assign(:query, query)
      |> assign(:error, nil)
      |> assign(:just_added, false)

    # Perform search synchronously - Dictionary.lookup has caching
    socket = perform_search_sync(socket, query, user_id)

    {:noreply, socket}
  end

  def handle_event("add_to_study", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    result = socket.assigns.result

    case create_and_add_word(user_id, result) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> assign(:just_added, true)
         |> assign(:already_studying, true)}

      {:error, reason} ->
        Logger.warning("Failed to add word to study: #{inspect(reason)}")
        {:noreply, assign(socket, :error, "Failed to add word to study. Please try again.")}
    end
  end

  defp perform_search_sync(socket, query, user_id) do
    pref = Accounts.get_user_preference(user_id) || default_preferences()
    language = pref.target_language
    target = pref.native_language

    # Pass user_id to Dictionary.lookup for provider resolution
    # api_key is still passed for backward compatibility but resolver will use user config
    api_key = GoogleTranslateConfig.get_api_key(user_id)

    # Dictionary.lookup may return {:ok, result} or {:error, reason}
    case Dictionary.lookup(query,
           language: language,
           target: target,
           api_key: api_key,
           user_id: user_id
         ) do
      {:ok, result} ->
        handle_search_result(socket, result, language, query)

      {:error, :no_provider_available} ->
        put_flash(
          socket,
          :error,
          gettext(
            "Please configure Google Translate or an LLM in settings to use dictionary lookups."
          )
        )
    end
  end

  defp handle_search_result(socket, result, language, query) do
    # Check if we got meaningful results
    has_content? =
      result.definitions != [] ||
        (result.translation != nil && result.translation != "")

    if has_content? do
      # Check if word exists in DB
      normalized = Vocabulary.normalize_form(result.word)
      word = Vocabulary.get_word_by_normalized_form(normalized, language)
      word_id = if word, do: word.id, else: nil

      # Check if already studying
      user_id = socket.assigns.current_scope.user.id

      already_studying =
        if word_id do
          Study.get_item_by_user_and_word(user_id, word_id) != nil
        else
          false
        end

      # Fetch conjugations for verbs
      conjugations = maybe_fetch_conjugations(result, language)

      socket
      |> assign(:result, result)
      |> assign(:conjugations, conjugations)
      |> assign(:word_id, word_id)
      |> assign(:already_studying, already_studying)
      |> assign(:error, nil)
    else
      Logger.warning("Dictionary lookup returned empty result for: #{query}")

      socket
      |> assign(:result, nil)
      |> assign(:conjugations, nil)
      |> assign(:word_id, nil)
      |> assign(:already_studying, false)
      |> assign(:error, "Could not find definition. Please try another word.")
    end
  end

  defp maybe_fetch_conjugations(result, language) do
    if verb?(result) do
      fetch_conjugations_for_verb(result, language)
    else
      nil
    end
  end

  defp verb?(result) do
    (is_binary(result.part_of_speech) &&
       String.downcase(result.part_of_speech) in ["verb", "verbo"]) ||
      Enum.any?(result.definitions, fn def ->
        is_binary(def) && String.contains?(String.downcase(def), "(verb)")
      end)
  end

  defp fetch_conjugations_for_verb(result, language) do
    lemma = result.lemma || result.word

    if is_binary(lemma) && lemma != "" do
      try_fetch_conjugations(lemma, language)
    else
      Logger.warning("No lemma or word available for conjugation fetch")
      nil
    end
  end

  defp try_fetch_conjugations(lemma, language) do
    normalized_lemma = normalize_lemma_for_wiktionary(lemma)

    case Conjugations.fetch_conjugations(normalized_lemma, language) do
      {:ok, conjugations} ->
        conjugations

      {:error, {:http_error, 404}} ->
        try_lowercase_fallback(lemma, normalized_lemma, language)

      {:error, reason} ->
        log_conjugation_error(lemma, language, reason)
        nil
    end
  end

  defp try_lowercase_fallback(lemma, normalized_lemma, language) do
    lower_lemma = String.downcase(lemma)

    if lower_lemma != normalized_lemma do
      case Conjugations.fetch_conjugations(lower_lemma, language) do
        {:ok, conjugations} ->
          conjugations

        {:error, reason} ->
          log_conjugation_fallback_error(lemma, normalized_lemma, lower_lemma, reason)
      end
    else
      Logger.warning("Failed to fetch conjugations for #{lemma} (#{language}): 404")
      nil
    end
  end

  defp log_conjugation_error(lemma, language, reason) do
    Logger.warning("Failed to fetch conjugations for #{lemma} (#{language}): #{inspect(reason)}")
  end

  defp log_conjugation_fallback_error(lemma, normalized_lemma, lower_lemma, reason) do
    Logger.warning(
      "Failed to fetch conjugations for #{lemma} (tried #{normalized_lemma} and #{lower_lemma}): #{inspect(reason)}"
    )

    nil
  end

  defp normalize_lemma_for_wiktionary(term) when is_binary(term) do
    # Capitalize first letter while preserving the rest (title case)
    case String.split_at(term, 1) do
      {"", _} -> term
      {first, rest} -> String.upcase(first) <> String.downcase(rest)
    end
  end

  defp normalize_lemma_for_wiktionary(_), do: nil

  defp create_and_add_word(user_id, result) do
    pref = Accounts.get_user_preference(user_id) || default_preferences()
    language = pref.target_language

    word_attrs = %{
      normalized_form: result.word,
      lemma: result.lemma || result.word,
      language: language,
      part_of_speech: result.part_of_speech,
      definitions: result.definitions || []
    }

    case Vocabulary.get_or_create_word(word_attrs) do
      {:ok, word} -> Study.schedule_new_item(user_id, word.id)
      error -> error
    end
  end

  defp default_preferences do
    %{target_language: "spanish", native_language: "en"}
  end
end

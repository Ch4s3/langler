defmodule LanglerWeb.StudyComponents do
  @moduledoc """
  Reusable UI components for study functionality.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: LanglerWeb.Endpoint,
    router: LanglerWeb.Router,
    statics: LanglerWeb.static_paths()

  import LanglerWeb.CoreComponents

  @doc """
  Renders the CSV import modal for bulk importing words into a deck.

  ## Examples

      <.csv_import_modal
        show={@show_csv_import}
        decks={@decks}
        csv_import_deck_id={@csv_import_deck_id}
        csv_preview={@csv_preview}
        csv_importing={@csv_importing}
        default_language={@default_language}
        uploads={@uploads}
      />
  """
  attr :show, :boolean, required: true, doc: "Whether to show the modal"
  attr :decks, :list, required: true, doc: "List of deck structs"
  attr :csv_import_deck_id, :integer, default: nil, doc: "Selected deck ID for import"
  attr :csv_preview, :list, default: nil, doc: "Preview rows from parsed CSV"
  attr :csv_importing, :boolean, default: false, doc: "Whether import is in progress"
  attr :default_language, :string, default: "spanish", doc: "Default language for words"
  attr :uploads, :map, required: true, doc: "Uploads map with csv_file config"

  def csv_import_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="modal modal-open"
      phx-click="hide_csv_import"
      phx-key="escape"
      phx-window-keydown="hide_csv_import"
    >
      <div class="modal-box max-w-2xl" phx-click-away="hide_csv_import" phx-click="stop_propagation">
        <h3 class="text-lg font-bold">Import words from CSV</h3>
        <p class="text-sm text-base-content/70 mt-2">
          Upload a CSV file with words. Format: single column (word) or two columns (word, language).
        </p>

        <div class="form-control w-full mt-4">
          <label class="label">
            <span class="label-text">Select deck</span>
          </label>
          <select
            class="select select-bordered w-full"
            phx-change="validate_csv_deck"
            name="deck_id"
          >
            <option value="">Select a deck</option>
            <option
              :for={deck <- @decks}
              value={deck.id}
              selected={@csv_import_deck_id == deck.id}
            >
              {deck.name}
              <%= if deck.is_default do %>
                (Default)
              <% end %>
            </option>
          </select>
        </div>

        <form id="csv-import-form" phx-change="validate_csv_file" phx-submit="parse_csv">
          <div class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">CSV file</span>
            </label>
            <.live_file_input
              upload={@uploads.csv_file}
              class="file-input file-input-bordered w-full"
            />
            <label class="label">
              <span class="label-text-alt">
                CSV format: word or word,language (one word per line)
              </span>
            </label>
          </div>

          <div class="mt-4">
            <button
              type="submit"
              class="btn btn-primary"
              disabled={Enum.empty?(@uploads.csv_file.entries)}
            >
              Load CSV
            </button>
          </div>
        </form>

        <div :if={@csv_preview} class="mt-6">
          <h4 class="text-sm font-semibold mb-2">Preview (first 10 rows):</h4>
          <div class="overflow-x-auto">
            <table class="table table-zebra table-sm">
              <thead>
                <tr>
                  <th>Word</th>
                  <th>Language</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{word, language} <- @csv_preview}>
                  <td>{word}</td>
                  <td>{language || @default_language}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="mt-4 flex gap-2">
            <button
              type="button"
              class="btn btn-primary"
              phx-click="import_csv"
              phx-value-deck_id={@csv_import_deck_id}
              disabled={is_nil(@csv_import_deck_id)}
            >
              Import words
            </button>
          </div>
        </div>

        <div class="modal-action">
          <button type="button" class="btn btn-ghost" phx-click="hide_csv_import">
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the deck management modal for creating or editing decks.

  ## Examples

      <.deck_modal
        show={@show_deck_modal}
        editing_deck={@editing_deck}
        form={@deck_form}
      />
  """
  attr :show, :boolean, required: true, doc: "Whether to show the modal"
  attr :editing_deck, :map, default: nil, doc: "The deck being edited, or nil for new deck"
  attr :form, :map, required: true, doc: "The form data from to_form/2"

  def deck_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="modal modal-open"
      phx-click="hide_deck_modal"
      phx-key="escape"
      phx-window-keydown="hide_deck_modal"
    >
      <div class="modal-box" phx-click-away="hide_deck_modal" phx-click="stop_propagation">
        <h3 class="text-lg font-bold">
          <%= if @editing_deck do %>
            Edit deck
          <% else %>
            Create new deck
          <% end %>
        </h3>
        <.form
          for={@form}
          id="deck-form"
          phx-submit={if @editing_deck, do: "update_deck", else: "create_deck"}
          phx-change="validate_deck"
        >
          <input
            type="hidden"
            name="deck_id"
            value={if @editing_deck, do: @editing_deck.id, else: ""}
          />
          <div class="form-control w-full">
            <label class="label">
              <span class="label-text">Deck name</span>
            </label>
            <.input
              field={@form[:name]}
              type="text"
              placeholder="Enter deck name"
              class="input input-bordered w-full"
              autofocus
            />
          </div>
          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="hide_deck_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              <%= if @editing_deck do %>
                Update
              <% else %>
                Create
              <% end %>
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @doc """
  Renders the "Your decks" section with deck cards and management actions.

  ## Examples

      <.decks_section decks={@decks} />
  """
  attr :decks, :list, required: true, doc: "List of deck structs"

  def decks_section(assigns) do
    ~H"""
    <div class="card section-card bg-base-100/95">
      <div class="card-body gap-4">
        <div class="flex items-center justify-between">
          <h2 class="card-title">
            <.icon name="hero-folder" class="h-6 w-6 text-primary" /> Your decks
          </h2>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="show_csv_import"
              class="btn btn-sm btn-secondary text-white"
            >
              <.icon name="hero-arrow-up-tray" class="h-4 w-4" />
              <span class="hidden sm:inline">Import CSV</span>
            </button>
            <button
              type="button"
              phx-click="show_deck_modal"
              class="btn btn-sm btn-primary text-white"
            >
              <.icon name="hero-plus" class="h-4 w-4" /> New deck
            </button>
          </div>
        </div>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={deck <- @decks}
            class="card bg-base-200/50 border border-base-300"
          >
            <div class="card-body gap-2">
              <div class="flex items-start justify-between">
                <h3 class="card-title text-base">
                  {deck.name}
                  <%= if deck.is_default do %>
                    <span class="badge badge-primary badge-sm">Default</span>
                  <% end %>
                </h3>
                <div class="dropdown dropdown-end">
                  <div tabindex="0" role="button" class="btn btn-ghost btn-xs">
                    <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
                  </div>
                  <ul
                    tabindex="0"
                    class="dropdown-content menu bg-base-100 rounded-box z-[1] w-32 border border-base-300 p-2 shadow-lg"
                  >
                    <li :if={not deck.is_default}>
                      <button
                        type="button"
                        phx-click="set_default_deck"
                        phx-value-deck_id={deck.id}
                      >
                        <.icon name="hero-star" class="h-4 w-4" /> Set default
                      </button>
                    </li>
                    <li>
                      <button
                        type="button"
                        phx-click="edit_deck"
                        phx-value-deck_id={deck.id}
                      >
                        <.icon name="hero-pencil" class="h-4 w-4" /> Edit
                      </button>
                    </li>
                    <li>
                      <button
                        :if={not deck.is_default}
                        type="button"
                        phx-click="delete_deck"
                        phx-value-deck_id={deck.id}
                        phx-confirm="Delete this deck? Words will remain in your study bank."
                        class="text-error"
                      >
                        <.icon name="hero-trash" class="h-4 w-4" /> Delete
                      </button>
                    </li>
                  </ul>
                </div>
              </div>
              <p class="text-sm text-base-content/70">
                {Langler.Vocabulary.get_deck_word_count(deck.id)} words
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a grid of KPI cards from a list of card data.

  Each card item should be a map with:
  - `:title` - The card title (required)
  - `:value` - The main value to display (required)
  - `:meta` - Secondary text below the value (required)
  - `:value_class` - Optional CSS class for the value (defaults to "text-base-content")

  ## Examples

      <.kpi_cards
        cards={[
          %{title: "Due now", value: 5, meta: "Ready for immediate review", value_class: "text-primary"},
          %{title: "Due today", value: 12, meta: "Includes overdue & later today", value_class: "text-secondary"},
          %{title: "Total tracked", value: 150, meta: "Words in your study bank"}
        ]}
      />
  """
  attr :cards, :list,
    required: true,
    doc: "List of card maps with title, value, meta, and optional value_class"

  def kpi_cards(assigns) do
    ~H"""
    <div class="kpi-grid">
      <div
        :for={card <- @cards}
        class="kpi-card"
      >
        <p class="kpi-card__title">{Map.get(card, :title, Map.get(card, "title", ""))}</p>
        <p class={[
          "kpi-card__value",
          Map.get(card, :value_class, Map.get(card, "value_class", "text-base-content"))
        ]}>
          {Map.get(card, :value, Map.get(card, "value", ""))}
        </p>
        <p class="kpi-card__meta">{Map.get(card, :meta, Map.get(card, "meta", ""))}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a study card for a single FSRS item.

  ## Examples

      <.study_card
        item={item}
        flipped={MapSet.member?(@flipped_cards, item.id)}
        definitions_loading={MapSet.member?(@definitions_loading || MapSet.new(), item.id)}
        conjugations_loading={MapSet.member?(@conjugations_loading || MapSet.new(), item.word.id)}
        expanded_conjugations={MapSet.member?(@expanded_conjugations, item.word.id)}
        quality_buttons={@quality_buttons}
      />
  """
  attr :item, :map, required: true, doc: "The FSRS item to display"
  attr :id, :string, default: nil, doc: "Optional DOM ID for the card (for streams)"
  attr :flipped, :boolean, default: false, doc: "Whether the card is flipped to show definition"
  attr :definitions_loading, :boolean, default: false, doc: "Whether definitions are being loaded"

  attr :conjugations_loading, :boolean,
    default: false,
    doc: "Whether conjugations are being loaded"

  attr :expanded_conjugations, :boolean,
    default: false,
    doc: "Whether conjugations section is expanded"

  attr :quality_buttons, :list, required: true, doc: "List of quality rating buttons"

  slot :conjugations, doc: "Conjugations section slot"
  slot :actions, doc: "Actions section slot (rating buttons)"

  def study_card(assigns) do
    card_id = assigns.id || "items-#{assigns.item.id}"
    is_phrase = assigns.item.word && Map.get(assigns.item.word, :type) == "phrase"

    assigns =
      assigns
      |> assign(:card_id, card_id)
      |> assign(:is_phrase, is_phrase)

    ~H"""
    <.card
      id={@card_id}
      variant={:panel}
      hover
      class="border border-base-200 animate-fade-in overflow-visible"
      body_class="overflow-visible"
    >
      <button
        type="button"
        phx-click="toggle_card"
        phx-value-id={@item.id}
        phx-hook="WordCardToggle"
        id={"study-card-#{@item.id}"}
        data-item-id={@item.id}
        class="group relative w-full rounded-2xl border border-dashed border-base-200 bg-base-100/80 p-4 text-left shadow-sm transition duration-300 hover:border-primary/40 hover:shadow-lg active:scale-[0.995] focus-visible:ring focus-visible:ring-primary/40 phx-click-loading:opacity-70"
      >
        <% definitions = @item.word && (@item.word.definitions || []) %>
        <div class="relative min-h-[12rem] sm:min-h-[16rem]">
          <div class={[
            "space-y-4 transition-opacity duration-300",
            @flipped && "hidden"
          ]}>
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div class="flex flex-col gap-1">
                <div class="flex items-center gap-2">
                  <p
                    class="inline-flex items-center gap-2 text-2xl font-semibold text-base-content cursor-pointer transition hover:text-primary sm:text-3xl"
                    phx-hook="CopyToClipboard"
                    data-copy-text={@item.word && (@item.word.lemma || @item.word.normalized_form)}
                    title="Click to copy"
                    id={"study-card-word-#{@item.id}"}
                  >
                    <span>{@item.word && (@item.word.lemma || @item.word.normalized_form)}</span>
                    <span
                      class="opacity-0 text-primary/80 transition-opacity duration-200 group-hover:opacity-100 pointer-events-none"
                      aria-hidden="true"
                    >
                      <.icon name="hero-clipboard-document" class="h-5 w-5" />
                    </span>
                  </p>
                  <span :if={@is_phrase} class="badge badge-secondary badge-sm">Phrase</span>
                </div>
                <p class="text-sm text-base-content/70">
                  Next review {format_due_label(@item.due_date)}
                </p>
              </div>
              <span class={[
                "badge badge-lg border",
                due_badge_class(@item.due_date)
              ]}>
                {due_status_label(@item.due_date)}
              </span>
            </div>

            <div class="flex flex-col gap-4 text-sm text-base-content/70 sm:flex-row sm:flex-wrap sm:gap-6">
              <div>
                <p class="font-semibold text-base-content">Ease factor</p>
                <p>{format_decimal(@item.ease_factor || 2.5)}</p>
              </div>
              <div>
                <p class="font-semibold text-base-content">Interval</p>
                <p>{interval_label(@item.interval)}</p>
              </div>
              <div>
                <p class="font-semibold text-base-content">Repetitions</p>
                <p>{@item.repetitions || 0}</p>
              </div>
              <div>
                <p class="font-semibold text-base-content">Recent history</p>
                <div class="flex gap-1">
                  <span
                    :for={score <- recent_history(@item.quality_history)}
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
              Tap to reveal {if @is_phrase, do: "translation", else: "definition"}
            </p>
          </div>

          <div class={[
            "flex flex-col gap-3 rounded-xl border border-primary/30 bg-primary/5 p-4 text-base-content transition-opacity duration-300 sm:gap-4",
            @flipped && "block",
            !@flipped && "hidden"
          ]}>
            <p class="text-sm font-semibold uppercase tracking-widest text-primary/70">
              {if @is_phrase, do: "Translation", else: "Definition"}
            </p>
            <%= if @definitions_loading do %>
              <div class="flex items-center gap-2">
                <span class="loading loading-spinner loading-sm"></span>
                <span class="text-sm text-base-content/70">
                  Loading {if @is_phrase, do: "translation", else: "definition"}...
                </span>
              </div>
            <% else %>
              <%= if @is_phrase do %>
                <p class="text-base text-base-content/90 break-words">
                  {@item.word.translation || List.first(definitions) || "No translation available"}
                </p>
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
            <% end %>
            <p class="text-xs text-base-content/60">Tap again to return.</p>
          </div>
        </div>
      </button>

      <:conjugations>
        {render_slot(@conjugations)}
      </:conjugations>

      <:actions>
        {render_slot(@actions)}
      </:actions>
    </.card>
    """
  end

  # Helper functions for study_card component

  defp format_decimal(nil), do: "0.0×"
  defp format_decimal(value), do: "#{Float.round(value, 2)}×"

  defp interval_label(nil), do: "New"
  defp interval_label(0), do: "Learning"
  defp interval_label(days), do: "#{days}d"

  defp due_badge_class(due_date) do
    if Langler.Study.due_now?(%{due_date: due_date}, DateTime.utc_now()) do
      "badge-error/20 text-error border-error/40"
    else
      "badge-success/20 text-success border-success/40"
    end
  end

  defp due_status_label(due_date) do
    if Langler.Study.due_now?(%{due_date: due_date}, DateTime.utc_now()) do
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

  @doc """
  Renders the recommended articles section.

  ## Examples

      <.recommended_articles_section
        recommended_articles={@recommended_articles}
        filter={@filter}
        user_level={@user_level}
      />
  """
  attr :recommended_articles, :any,
    required: true,
    doc: "AsyncResult assign for recommended articles"

  attr :filter, :atom, required: true, doc: "Current filter (:now, :today, :all)"
  attr :user_level, :map, required: true, doc: "User vocabulary level with cefr_level"

  def recommended_articles_section(assigns) do
    ~H"""
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

          <.card_grid>
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
          </.card_grid>
        </div>
      </div>
    </.async_result>
    """
  end
end

defmodule LanglerWeb.DeckComponents do
  @moduledoc """
  Reusable UI components for deck management functionality.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: LanglerWeb.Endpoint,
    router: LanglerWeb.Router,
    statics: LanglerWeb.static_paths()

  import LanglerWeb.CoreComponents

  @doc """
  Renders a deck card with expand/collapse functionality.

  Implementation note (daisyUI 5):
  - Uses collapse component for expandable deck contents

  ## Variants by context:
  - :owned - Full control (edit, delete, share, drag words)
  - :followed - Read-only with unfollow/copy actions
  - :shared - Based on permission level
  - :discover - Preview with follow/copy actions
  """
  attr :deck, :map, required: true
  attr :variant, :atom, default: :owned
  attr :expanded, :boolean, default: false
  attr :words, :list, default: []
  attr :custom_cards, :list, default: []
  attr :word_count, :integer, required: true
  attr :owner, :map, default: nil
  attr :follower_count, :integer, default: 0

  def deck_card(assigns) do
    ~H"""
    <div
      id={"deck-#{@deck.id}"}
      class={[
        "card bg-base-100 border border-base-200 transition-all duration-300",
        @expanded && "ring-2 ring-primary/20",
        @deck.is_default && "border-l-4 border-l-warning"
      ]}
      phx-hook={if @variant == :owned, do: "DeckDropZone", else: nil}
      data-deck-id={@deck.id}
    >
      <div class="card-body p-4 gap-3">
        <%!-- Header Row --%>
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <span :if={@deck.is_default} class="text-warning" title="Default deck">★</span>
              <h3 class="font-semibold text-base truncate">{@deck.name}</h3>
              <.visibility_badge visibility={@deck.visibility} />
            </div>
            <p :if={@deck.description} class="text-sm text-base-content/60 truncate mt-0.5">
              {@deck.description}
            </p>
            <p :if={@owner} class="text-xs text-base-content/50 mt-1">
              by {@owner.email}
              <span :if={@follower_count > 0} class="ml-2">
                👥 {format_count(@follower_count)}
              </span>
            </p>
          </div>

          <%!-- Word Count Badge --%>
          <div class="flex-shrink-0 text-center px-3 py-2 bg-base-200/50 rounded-lg">
            <div class="text-2xl font-bold text-primary">{@word_count}</div>
            <div class="text-xs text-base-content/60">cards</div>
          </div>
        </div>

        <%!-- Expand/Collapse + Actions Row --%>
        <div class="flex items-center justify-between pt-2 border-t border-base-200">
          <button
            type="button"
            phx-click="toggle_deck_expanded"
            phx-value-deck-id={@deck.id}
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon
              name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"}
              class="h-4 w-4"
            />
            {if @expanded, do: "Collapse", else: "Expand"}
          </button>

          <.deck_actions deck={@deck} variant={@variant} />
        </div>

        <%!-- Expanded Contents --%>
        <div :if={@expanded} class="mt-2 animate-fade-in">
          <.deck_contents
            words={@words}
            custom_cards={@custom_cards}
            deck_id={@deck.id}
            editable={@variant == :owned}
          />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders deck action buttons based on variant.
  """
  attr :deck, :map, required: true
  attr :variant, :atom, required: true

  def deck_actions(assigns) do
    ~H"""
    <%= cond do %>
      <% @variant == :owned -> %>
        <div class="dropdown dropdown-end">
          <div tabindex="0" role="button" class="btn btn-ghost btn-xs">
            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-box z-[1] w-40 border border-base-300 p-2 shadow-lg"
          >
            <li :if={not @deck.is_default}>
              <button type="button" phx-click="set_default_deck" phx-value-deck-id={@deck.id}>
                <.icon name="hero-star" class="h-4 w-4" /> Set default
              </button>
            </li>
            <li>
              <button type="button" phx-click="edit_deck" phx-value-deck-id={@deck.id}>
                <.icon name="hero-pencil" class="h-4 w-4" /> Edit
              </button>
            </li>
            <li>
              <button type="button" phx-click="set_visibility" phx-value-deck-id={@deck.id}>
                <.icon name="hero-eye" class="h-4 w-4" /> Visibility
              </button>
            </li>
            <li :if={not @deck.is_default}>
              <button
                type="button"
                phx-click="delete_deck"
                phx-value-deck-id={@deck.id}
                phx-confirm="Delete this deck? Cards will remain in your study bank."
                class="text-error"
              >
                <.icon name="hero-trash" class="h-4 w-4" /> Delete
              </button>
            </li>
          </ul>
        </div>
      <% @variant == :followed -> %>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="unfollow_deck"
            phx-value-deck-id={@deck.id}
            class="btn btn-ghost btn-xs"
          >
            Unfollow
          </button>
          <button
            type="button"
            phx-click="freeze_deck"
            phx-value-deck-id={@deck.id}
            class="btn btn-ghost btn-xs"
          >
            Freeze
          </button>
          <button
            type="button"
            phx-click="copy_deck"
            phx-value-deck-id={@deck.id}
            class="btn btn-primary btn-xs text-white"
          >
            Copy
          </button>
        </div>
      <% @variant == :discover -> %>
        <div class="flex gap-2">
          <button
            type="button"
            phx-click="follow_deck"
            phx-value-deck-id={@deck.id}
            class="btn btn-ghost btn-xs"
          >
            Follow
          </button>
          <button
            type="button"
            phx-click="copy_deck"
            phx-value-deck-id={@deck.id}
            class="btn btn-primary btn-xs text-white"
          >
            Copy
          </button>
        </div>
      <% true -> %>
        <div></div>
    <% end %>
    """
  end

  @doc """
  Renders deck contents (words + custom cards) in a scrollable list.
  """
  attr :words, :list, required: true
  attr :custom_cards, :list, default: []
  attr :deck_id, :integer, required: true
  attr :editable, :boolean, default: false

  def deck_contents(assigns) do
    ~H"""
    <div class="space-y-3">
      <%!-- Words Section --%>
      <div
        :if={@words != []}
        class="max-h-80 overflow-y-auto rounded-lg border border-base-200 bg-base-200/30"
      >
        <table class="table table-sm table-pin-rows">
          <thead>
            <tr class="bg-base-200">
              <th :if={@editable} class="w-8"></th>
              <th>Word</th>
              <th class="hidden sm:table-cell">Definition</th>
              <th class="w-20">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={word <- @words}
              id={"word-row-#{@deck_id}-#{word.id}"}
              class="hover:bg-base-100 group"
              draggable={if @editable, do: "true", else: "false"}
              phx-hook={if @editable, do: "DraggableWord", else: nil}
              data-word-id={word.id}
              data-deck-id={@deck_id}
              data-card-type="word"
            >
              <td :if={@editable} class="cursor-grab active:cursor-grabbing">
                <.icon
                  name="hero-bars-3"
                  class="h-4 w-4 text-base-content/40 group-hover:text-base-content/70"
                />
              </td>
              <td class="font-medium">
                {word.lemma || word.normalized_form}
                <span :if={word.type == "phrase"} class="badge badge-secondary badge-xs ml-1">
                  phrase
                </span>
              </td>
              <td class="hidden sm:table-cell text-sm text-base-content/70 max-w-xs truncate">
                {List.first(word.definitions) || "—"}
              </td>
              <td>
                <button
                  :if={@editable}
                  type="button"
                  phx-click="remove_word_from_deck"
                  phx-value-deck-id={@deck_id}
                  phx-value-word-id={word.id}
                  class="btn btn-ghost btn-xs text-error"
                  title="Remove from deck"
                >
                  <.icon name="hero-x-mark" class="h-4 w-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Custom Cards Section --%>
      <div
        :if={@custom_cards != []}
        class="max-h-80 overflow-y-auto rounded-lg border border-base-200 bg-base-200/30"
      >
        <div class="p-2 bg-base-200 text-xs font-semibold text-base-content/70">Custom Cards</div>
        <table class="table table-sm">
          <thead>
            <tr>
              <th :if={@editable} class="w-8"></th>
              <th>Front</th>
              <th class="hidden sm:table-cell">Back</th>
              <th class="w-20">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={card <- @custom_cards}
              id={"custom-card-row-#{@deck_id}-#{card.id}"}
              class="hover:bg-base-100 group"
              draggable={if @editable, do: "true", else: "false"}
              phx-hook={if @editable, do: "DraggableWord", else: nil}
              data-word-id={card.id}
              data-deck-id={@deck_id}
              data-card-type="custom_card"
            >
              <td :if={@editable} class="cursor-grab active:cursor-grabbing">
                <.icon
                  name="hero-bars-3"
                  class="h-4 w-4 text-base-content/40 group-hover:text-base-content/70"
                />
              </td>
              <td class="font-medium max-w-xs truncate">
                {card.front}
              </td>
              <td class="hidden sm:table-cell text-sm text-base-content/70 max-w-xs truncate">
                {card.back}
              </td>
              <td>
                <div class="flex gap-1">
                  <button
                    :if={@editable}
                    type="button"
                    phx-click="edit_custom_card"
                    phx-value-card-id={card.id}
                    class="btn btn-ghost btn-xs"
                    title="Edit card"
                  >
                    <.icon name="hero-pencil" class="h-4 w-4" />
                  </button>
                  <button
                    :if={@editable}
                    type="button"
                    phx-click="remove_custom_card_from_deck"
                    phx-value-deck-id={@deck_id}
                    phx-value-card-id={card.id}
                    class="btn btn-ghost btn-xs text-error"
                    title="Remove from deck"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Empty State --%>
      <div :if={@words == [] and @custom_cards == []} class="p-8 text-center text-base-content/60">
        <.icon name="hero-inbox" class="h-8 w-8 mx-auto mb-2 opacity-50" />
        <p>No cards in this deck yet</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders visibility badge with icon.
  """
  attr :visibility, :string, required: true

  def visibility_badge(assigns) do
    ~H"""
    <span class={["badge badge-sm gap-1", visibility_class(@visibility)]}>
      <.icon name={visibility_icon(@visibility)} class="h-3 w-3" />
      <span class="hidden sm:inline">{@visibility}</span>
    </span>
    """
  end

  defp visibility_icon("private"), do: "hero-lock-closed"
  defp visibility_icon("shared"), do: "hero-user-group"
  defp visibility_icon("public"), do: "hero-globe-alt"
  defp visibility_icon(_), do: "hero-lock-closed"

  defp visibility_class("private"), do: "badge-ghost"
  defp visibility_class("shared"), do: "badge-info badge-outline"
  defp visibility_class("public"), do: "badge-success badge-outline"
  defp visibility_class(_), do: "badge-ghost"

  @doc """
  Renders LLM suggestion card.
  """
  attr :suggestion, :map, required: true
  attr :index, :integer, required: true
  attr :expanded, :boolean, default: false

  def suggestion_card(assigns) do
    ~H"""
    <div class={[
      "card bg-base-100 border transition-all duration-200",
      category_border_class(@suggestion.category)
    ]}>
      <div class="card-body gap-3">
        <div class="flex items-start justify-between">
          <div class="flex items-center gap-2">
            <span class="text-xl">{category_emoji(@suggestion.category)}</span>
            <h3 class="card-title text-base">{@suggestion.name}</h3>
          </div>
          <span class={["badge badge-sm", category_badge_class(@suggestion.category)]}>
            {String.upcase(@suggestion.category)}
          </span>
        </div>

        <p class="text-sm text-base-content/70">{@suggestion.description}</p>

        <div class="flex flex-wrap gap-1.5">
          <span
            :for={word <- Enum.take(@suggestion.words, if(@expanded, do: 100, else: 8))}
            class="badge badge-outline badge-sm"
          >
            {word}
          </span>
          <button
            :if={length(@suggestion.words) > 8 and not @expanded}
            type="button"
            phx-click="toggle_suggestion_expanded"
            phx-value-index={@index}
            class="badge badge-ghost badge-sm cursor-pointer"
          >
            +{length(@suggestion.words) - 8} more
          </button>
        </div>

        <div class="flex items-center justify-between pt-2 border-t border-base-200">
          <span class="text-xs text-base-content/60">
            {length(@suggestion.words)} words · {trunc(@suggestion.confidence * 100)}% confidence
          </span>
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="dismiss_suggestion"
              phx-value-index={@index}
              class="btn btn-ghost btn-xs"
            >
              <.icon name="hero-x-mark" class="h-4 w-4" /> Dismiss
            </button>
            <button
              type="button"
              phx-click="accept_suggestion"
              phx-value-index={@index}
              class="btn btn-primary btn-xs text-white"
            >
              <.icon name="hero-check" class="h-4 w-4" /> Create
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp category_emoji("thematic"), do: "🏷️"
  defp category_emoji("grammatical"), do: "📐"
  defp category_emoji("difficulty"), do: "📊"
  defp category_emoji(_), do: "📦"

  defp category_border_class("thematic"), do: "border-l-4 border-l-primary"
  defp category_border_class("grammatical"), do: "border-l-4 border-l-secondary"
  defp category_border_class("difficulty"), do: "border-l-4 border-l-accent"
  defp category_border_class(_), do: "border-l-4 border-l-base-300"

  defp category_badge_class("thematic"), do: "badge-primary"
  defp category_badge_class("grammatical"), do: "badge-secondary"
  defp category_badge_class("difficulty"), do: "badge-accent"
  defp category_badge_class(_), do: "badge-ghost"

  @doc """
  Renders the deck creation/edit modal.
  """
  attr :show, :boolean, required: true
  attr :editing_deck, :map, default: nil
  attr :form, :map, required: true

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
          id="deck-modal-form"
          phx-submit={if @editing_deck, do: "update_deck", else: "create_deck"}
          phx-change="validate_deck"
        >
          <input
            type="hidden"
            name="deck_id"
            value={if @editing_deck, do: @editing_deck.id, else: ""}
          />

          <div class="form-control w-full mt-4">
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

          <div class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">Description (optional)</span>
            </label>
            <.input
              field={@form[:description]}
              type="textarea"
              placeholder="Brief description of this deck"
              class="textarea textarea-bordered w-full"
            />
          </div>

          <div class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">Visibility</span>
            </label>
            <div class="space-y-2">
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  type="radio"
                  name="visibility"
                  value="private"
                  checked={@form[:visibility].value == "private"}
                  class="radio radio-sm"
                />
                <span class="label-text">
                  <.icon name="hero-lock-closed" class="h-4 w-4 inline" /> Private - Only you
                </span>
              </label>
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  type="radio"
                  name="visibility"
                  value="shared"
                  checked={@form[:visibility].value == "shared"}
                  class="radio radio-sm"
                />
                <span class="label-text">
                  <.icon name="hero-user-group" class="h-4 w-4 inline" /> Shared - Specific people
                </span>
              </label>
              <label class="label cursor-pointer justify-start gap-2">
                <input
                  type="radio"
                  name="visibility"
                  value="public"
                  checked={@form[:visibility].value == "public"}
                  class="radio radio-sm"
                />
                <span class="label-text">
                  <.icon name="hero-globe-alt" class="h-4 w-4 inline" /> Public - Anyone can follow
                </span>
              </label>
            </div>
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
  Renders the custom card creation/edit modal.
  """
  attr :show, :boolean, required: true
  attr :editing_card, :map, default: nil
  attr :form, :map, required: true
  attr :decks, :list, required: true

  def custom_card_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="modal modal-open"
      phx-click="hide_custom_card_modal"
      phx-key="escape"
      phx-window-keydown="hide_custom_card_modal"
    >
      <div class="modal-box" phx-click-away="hide_custom_card_modal" phx-click="stop_propagation">
        <h3 class="text-lg font-bold">
          <%= if @editing_card do %>
            Edit custom card
          <% else %>
            Create custom card
          <% end %>
        </h3>
        <.form
          for={@form}
          id="custom-card-form"
          phx-submit={if @editing_card, do: "update_custom_card", else: "create_custom_card"}
          phx-change="validate_custom_card"
        >
          <input
            type="hidden"
            name="card_id"
            value={if @editing_card, do: @editing_card.id, else: ""}
          />

          <div class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">Front (question/word)</span>
            </label>
            <.input
              field={@form[:front]}
              type="textarea"
              placeholder="¿Cómo se dice 'hello'?"
              class="textarea textarea-bordered w-full"
              autofocus
            />
          </div>

          <div class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">Back (answer)</span>
            </label>
            <.input
              field={@form[:back]}
              type="textarea"
              placeholder="Hola"
              class="textarea textarea-bordered w-full"
            />
          </div>

          <div :if={!@editing_card} class="form-control w-full mt-4">
            <label class="label">
              <span class="label-text">Add to deck</span>
            </label>
            <select name="deck_id" class="select select-bordered w-full">
              <option :for={deck <- @decks} value={deck.id}>
                {deck.name}
                <%= if deck.is_default do %>
                  (Default)
                <% end %>
              </option>
            </select>
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="hide_custom_card_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              <%= if @editing_card do %>
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
  Renders suggestions panel (modal or slide-in).
  """
  attr :show, :boolean, required: true
  attr :suggestions, :list, required: true
  attr :loading, :boolean, default: false
  attr :error, :any, default: nil
  attr :expanded_index, :any, default: nil

  def suggestions_panel(assigns) do
    ~H"""
    <div
      :if={@show}
      class="modal modal-open"
      phx-click="hide_suggestions_panel"
      phx-key="escape"
      phx-window-keydown="hide_suggestions_panel"
    >
      <div
        class="modal-box max-w-3xl"
        phx-click-away="hide_suggestions_panel"
        phx-click="stop_propagation"
      >
        <h3 class="text-lg font-bold">AI Deck Suggestions</h3>

        <%= cond do %>
          <% @loading -> %>
            <div class="flex flex-col items-center justify-center py-12 gap-4">
              <span class="loading loading-spinner loading-lg text-primary"></span>
              <p class="text-sm text-base-content/70">Analyzing your vocabulary...</p>
            </div>
          <% @error -> %>
            <div class="alert alert-error mt-4">
              <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
              <span>{format_error(@error)}</span>
            </div>
            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="hide_suggestions_panel">
                Close
              </button>
              <button type="button" class="btn btn-primary" phx-click="request_llm_suggestions">
                Try Again
              </button>
            </div>
          <% @suggestions != [] -> %>
            <p class="text-sm text-base-content/70 mt-2">
              We found {length(@suggestions)} potential groupings for your ungrouped words
            </p>

            <div class="space-y-3 mt-4 max-h-[60vh] overflow-y-auto">
              <.suggestion_card
                :for={{suggestion, idx} <- Enum.with_index(@suggestions)}
                suggestion={suggestion}
                index={idx}
                expanded={@expanded_index == idx}
              />
            </div>

            <div class="modal-action">
              <button type="button" class="btn btn-ghost" phx-click="hide_suggestions_panel">
                Close
              </button>
              <button type="button" class="btn btn-ghost" phx-click="dismiss_all_suggestions">
                Dismiss All
              </button>
              <button type="button" class="btn btn-primary" phx-click="accept_all_suggestions">
                Accept All ({length(@suggestions)})
              </button>
            </div>
          <% true -> %>
            <div class="flex flex-col items-center justify-center py-12">
              <.icon name="hero-light-bulb" class="h-12 w-12 text-base-content/30 mb-4" />
              <p class="text-sm text-base-content/70">No suggestions available</p>
            </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_error(:no_llm_config), do: "Please configure an LLM in settings to use this feature"

  defp format_error({:too_few_words, count}),
    do:
      "Need at least 10 words (you have #{count}). Add more words before requesting suggestions."

  defp format_error(:invalid_json), do: "Failed to parse LLM response. Please try again."
  defp format_error(:invalid_format), do: "LLM returned invalid format. Please try again."
  defp format_error(:timeout), do: "Request timed out. Please try again."

  defp format_error({:rate_limit_exceeded, retry_after}),
    do: "Rate limit exceeded. Please wait #{retry_after} seconds and try again."

  defp format_error(error), do: "An error occurred: #{inspect(error)}"

  @doc """
  Renders the ungrouped words banner.
  """
  attr :ungrouped_count, :integer, required: true

  def ungrouped_words_banner(assigns) do
    ~H"""
    <div :if={@ungrouped_count > 0} class="card bg-primary/10 border border-primary/30">
      <div class="card-body p-4 gap-3">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h3 class="font-semibold text-base flex items-center gap-2">
              <.icon name="hero-light-bulb" class="h-5 w-5 text-primary" />
              {@ungrouped_count} ungrouped words
            </h3>
            <p class="text-sm text-base-content/70 mt-1">
              Words in your default deck that aren't organized yet.
            </p>
          </div>
          <button
            type="button"
            phx-click="request_llm_suggestions"
            class="btn btn-primary btn-sm text-white"
          >
            <.icon name="hero-sparkles" class="h-4 w-4" /> Get AI Suggestions
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp format_count(count) when count >= 1000, do: "#{Float.round(count / 1000, 1)}k"
  defp format_count(count), do: to_string(count)
end

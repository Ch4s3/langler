defmodule LanglerWeb.StudyLive.Session do
  @moduledoc """
  Full-screen study session LiveView for focused card-by-card review.
  """

  use LanglerWeb, :live_view

  alias Langler.Repo
  alias Langler.Study
  alias Langler.Study.FSRS
  alias Langler.Vocabulary.DeckWord

  @quality_buttons [
    %{score: 0, label: "Again", class: "btn-error"},
    %{score: 2, label: "Hard", class: "btn-warning"},
    %{score: 3, label: "Good", class: "btn-primary"},
    %{score: 4, label: "Easy", class: "btn-success"}
  ]

  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    deck_id = parse_deck_id(params)
    cards = load_due_today_cards(scope.user.id, deck_id)

    {:ok,
     socket
     |> assign(:current_user, scope.user)
     |> assign(:cards, cards)
     |> assign(:current_index, 0)
     |> assign(:flipped, false)
     |> assign(:reviewed_count, 0)
     |> assign(:total_cards, length(cards))
     |> assign(:session_start, DateTime.utc_now())
     |> assign(:ratings, %{again: 0, hard: 0, good: 0, easy: 0})
     |> assign(:completed, false)
     |> assign(:quality_buttons, @quality_buttons)
     |> assign(:deck_id, deck_id)}
  end

  defp parse_deck_id(params) do
    case Map.get(params, "deck_id") do
      nil ->
        nil

      deck_id_str ->
        case Integer.parse(deck_id_str) do
          {deck_id, ""} -> deck_id
          _ -> nil
        end
    end
  end

  def render(assigns) do
    ~H"""
    <div
      id="study-session-fullscreen"
      class="fixed inset-0 z-40 bg-base-200 flex flex-col"
      phx-hook="StudySession"
    >
      <%= if @completed do %>
        {render_completion(assigns)}
      <% else %>
        <%= if @total_cards == 0 do %>
          {render_empty_state(assigns)}
        <% else %>
          {render_study_session(assigns)}
        <% end %>
      <% end %>
    </div>
    """
  end

  defp render_study_session(assigns) do
    assigns = assign(assigns, :current_card, Enum.at(assigns.cards, assigns.current_index))

    ~H"""
    <div id="study-session-container" class="flex-1 flex flex-col overflow-hidden min-h-0">
      <%!-- Compact header: Exit + Progress --%>
      <div class="flex items-center justify-between px-4 py-2 border-b border-base-200 bg-base-100/90 backdrop-blur flex-shrink-0">
        <.link
          id="study-session-exit"
          navigate={~p"/study"}
          class="btn btn-sm btn-ghost min-h-[44px] min-w-[44px] p-2"
          aria-label="Exit study session"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </.link>

        <div class="text-center flex-1">
          <div class="flex items-center justify-center gap-1.5 mb-1">
            <span
              :for={i <- 0..(assigns.total_cards - 1)}
              class={[
                "h-1.5 w-1.5 rounded-full transition-all duration-300",
                if(i < assigns.current_index, do: "bg-primary", else: "bg-base-300"),
                if(i == assigns.current_index, do: "h-2 w-2 bg-primary ring-1 ring-primary/30")
              ]}
              aria-label={"Card #{i + 1}"}
            />
          </div>
          <p class="text-[0.55rem] font-semibold uppercase tracking-[0.3em] text-base-content/50">
            Card {assigns.current_index + 1} of {assigns.total_cards}
          </p>
          <p class="text-xs font-semibold text-base-content/70">
            {assigns.current_index + 1}/{assigns.total_cards}
          </p>
        </div>

        <div class="min-w-[44px]"></div>
      </div>

      <%!-- Card container --%>
      <div
        id="study-card-container"
        class="study-card-container flex-1 min-h-0 flex items-center justify-center p-3 overflow-hidden"
      >
        <%= if @current_card && @current_card.word do %>
          <div class="w-full h-full max-w-2xl">
            {render_card(assigns, @current_card)}
          </div>
        <% else %>
          <div class="card bg-base-100 shadow-xl w-full">
            <div class="card-body text-center">
              <p class="text-base-content/70">Card data unavailable</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_card(assigns, item) do
    word = item.word
    definitions = word.definitions || []
    is_phrase = word && word.type == "phrase"

    assigns =
      assign(assigns, :word, word)
      |> assign(:definitions, definitions)
      |> assign(:item, item)
      |> assign(:is_phrase, is_phrase)

    ~H"""
    <div
      id="study-card"
      class={[
        "study-card w-full h-full cursor-pointer",
        assigns.flipped && "flipped"
      ]}
      phx-click="flip_card"
    >
      <div class="study-card-inner">
        <%!-- Front side - Word, Stats, Rating --%>
        <div class="study-card-face study-card-front">
          <.card
            variant={:default}
            class="h-full w-full flex flex-col bg-gradient-to-br from-base-100 to-base-200/50"
            body_class="flex flex-col h-full p-3 sm:p-6"
          >
            <%!-- Word --%>
            <div class="flex-[5] min-h-0 flex flex-col items-center justify-center sm:flex-1">
              <div class="flex flex-col items-center gap-2">
                <div class="flex items-center gap-2">
                  <p class="text-study-word font-semibold text-base-content text-center leading-tight">
                    {@word.lemma || @word.normalized_form}
                  </p>
                  <span :if={@is_phrase} class="badge badge-secondary badge-sm">Phrase</span>
                </div>
                <p class="text-xs text-base-content/60">
                  Tap to flip
                </p>
              </div>
            </div>

            <%!-- Compact Stats --%>
            <.card_stats
              item={@item}
              class="flex-none"
            />

            <:actions>
              <.card_rating_mobile
                item_id={@item.id}
                buttons={@quality_buttons}
                event="rate_card"
              />
            </:actions>
          </.card>
        </div>

        <%!-- Back side - Definition or Translation --%>
        <div class="study-card-face study-card-back">
          <.card
            variant={:default}
            class="h-full w-full flex flex-col bg-gradient-to-br from-primary/5 to-primary/10"
            body_class="flex flex-col h-full justify-center items-center p-4"
          >
            <div class="flex flex-col gap-3 items-center w-full overflow-auto">
              <p class="text-xs font-semibold uppercase tracking-widest text-primary/70">
                {if @is_phrase, do: "Translation", else: "Definition"}
              </p>
              <%= if @is_phrase do %>
                <p class="text-base sm:text-lg text-base-content/90 text-center break-words">
                  {@word.translation || List.first(@definitions) || "No translation available"}
                </p>
              <% else %>
                <%= if @definitions != [] do %>
                  <ol class="space-y-2 text-sm sm:text-base text-base-content/90 text-left w-full">
                    <li
                      :for={{definition, idx} <- Enum.with_index(@definitions, 1)}
                      class="flex gap-2 items-start break-words"
                    >
                      <span class="font-semibold text-primary/80 flex-shrink-0">{idx}.</span>
                      <span class="break-words">{definition}</span>
                    </li>
                  </ol>
                <% else %>
                  <p class="text-sm text-base-content/70">No definition available</p>
                <% end %>
              <% end %>
            </div>
          </.card>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :class, :string, default: ""

  defp card_stats(assigns) do
    ~H"""
    <div class={[
      "grid grid-cols-4 gap-1 text-[0.6rem] leading-tight border-t border-base-200 py-1 lg:gap-2 lg:text-[0.65rem]",
      @class
    ]}>
      <div class="text-center">
        <span class="font-semibold text-base-content/70">Ease</span>
        <p class="text-[0.55rem] leading-none">{format_decimal(@item.ease_factor || 2.5)}</p>
      </div>
      <div class="text-center">
        <span class="font-semibold text-base-content/70">Int</span>
        <p class="text-[0.55rem] leading-none">{interval_label(@item.interval)}</p>
      </div>
      <div class="text-center">
        <span class="font-semibold text-base-content/70">Reps</span>
        <p class="text-[0.55rem] leading-none">{@item.repetitions || 0}</p>
      </div>
      <div class="text-center">
        <span class="font-semibold text-base-content/70">Hist</span>
        <div class="flex gap-0.5 justify-center mt-0.5">
          <span
            :for={score <- recent_history(@item.quality_history)}
            class={[
              "h-1.5 w-2 rounded-full bg-base-300",
              history_pill_class(score)
            ]}
            aria-label={"Score #{score}"}
          />
        </div>
      </div>
    </div>
    """
  end

  defp render_completion(assigns) do
    time_spent = DateTime.diff(DateTime.utc_now(), assigns.session_start, :second)
    minutes = div(time_spent, 60)
    seconds = rem(time_spent, 60)
    assigns = assign(assigns, :minutes, minutes) |> assign(:seconds, seconds)

    ~H"""
    <div
      id="study-session-complete"
      class="flex-1 flex items-center justify-center p-4 animate-fade-in"
    >
      <div class="card bg-base-100 shadow-xl max-w-xl w-full sm:max-w-2xl max-h-[85vh] sm:max-h-none overflow-hidden">
        <div class="card-body gap-6 max-h-[85vh] sm:max-h-none overflow-y-auto sm:overflow-visible">
          <div class="text-center">
            <div class="mb-4">
              <.icon name="hero-check-circle" class="h-16 w-16 text-success mx-auto animate-fade-in" />
            </div>
            <h2 class="text-3xl font-bold text-base-content mb-2">Session Complete!</h2>
            <p class="text-base-content/70">Great work reviewing your cards</p>
          </div>

          <div class="divider"></div>

          <div class="space-y-4">
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Cards reviewed</span>
              <span class="text-2xl font-semibold text-primary">
                {assigns.reviewed_count} cards reviewed
              </span>
            </div>

            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Time spent</span>
              <span class="text-xl font-semibold text-base-content">
                {@minutes}m {@seconds}s
              </span>
            </div>

            <div class="divider"></div>

            <div>
              <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60 mb-3">
                Rating breakdown
              </p>
              <div class="space-y-2">
                <div class="flex justify-between items-center">
                  <span class="text-base-content/70">Again</span>
                  <span class="badge badge-error">{assigns.ratings.again}</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-base-content/70">Hard</span>
                  <span class="badge badge-warning">{assigns.ratings.hard}</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-base-content/70">Good</span>
                  <span class="badge badge-primary">{assigns.ratings.good}</span>
                </div>
                <div class="flex justify-between items-center">
                  <span class="text-base-content/70">Easy</span>
                  <span class="badge badge-success">{assigns.ratings.easy}</span>
                </div>
              </div>
            </div>
          </div>

          <div class="divider"></div>

          <div class="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:justify-center">
            <.link
              navigate={~p"/study"}
              class="btn btn-primary text-white w-full sm:w-auto sm:min-w-[180px]"
            >
              Return to Study Overview
            </.link>
            <.link
              navigate={~p"/study/session"}
              class="btn btn-outline w-full sm:w-auto sm:min-w-[180px]"
            >
              Start New Session
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_empty_state(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center p-4">
      <div class="card bg-base-100 shadow-xl max-w-md w-full">
        <div class="card-body text-center gap-4">
          <h2 class="text-2xl font-bold text-base-content">No cards due today</h2>
          <p class="text-base-content/70">You're all caught up! Check back later for more reviews.</p>
          <.link navigate={~p"/study"} class="btn btn-primary text-white mt-4">
            Return to Study Overview
          </.link>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("flip_card", _params, socket) do
    {:noreply, assign(socket, :flipped, !socket.assigns.flipped)}
  end

  def handle_event(
        "rate_card",
        %{"quality" => quality, "item_id" => item_id_str},
        socket
      )
      when is_binary(item_id_str) do
    process_rate_card(item_id_str, quality, socket)
  end

  def handle_event(
        "rate_card",
        %{"quality" => quality, "item-id" => item_id_str},
        socket
      )
      when is_binary(item_id_str) do
    process_rate_card(item_id_str, quality, socket)
  end

  def handle_event("rate_card", _params, socket), do: {:noreply, socket}

  defp process_rate_card(item_id_str, quality, socket) do
    with {item_id, ""} <- Integer.parse(item_id_str),
         current_card when not is_nil(current_card) <-
           Enum.at(socket.assigns.cards, socket.assigns.current_index),
         true <- current_card.id == item_id do
      rate_card(socket, item_id, quality)
    else
      _ ->
        {:noreply, socket}
    end
  end

  defp rate_card(socket, item_id, quality) do
    with {:ok, item} <- find_item(socket.assigns.cards, item_id),
         rating <- parse_quality(quality),
         {:ok, updated} <- Study.review_item(item, rating) do
      updated_cards = replace_item(socket.assigns.cards, updated)
      ratings = update_ratings(socket.assigns.ratings, rating)
      next_index = socket.assigns.current_index + 1
      completed = next_index >= length(updated_cards)

      {:noreply,
       socket
       |> assign(:cards, updated_cards)
       |> assign(
         :current_index,
         if(completed, do: socket.assigns.current_index, else: next_index)
       )
       |> assign(:flipped, false)
       |> assign(:reviewed_count, socket.assigns.reviewed_count + 1)
       |> assign(:ratings, ratings)
       |> assign(:completed, completed)}
    else
      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Unable to rate card: %{reason}", reason: inspect(reason))
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_due_today_cards(user_id, deck_id) do
    now = DateTime.utc_now()
    end_of_day = Study.end_of_day(now)

    Study.list_items_for_user(user_id)
    |> Enum.filter(fn item ->
      Study.due_today?(item, end_of_day) and not is_nil(item.word) and
        matches_deck?(item, deck_id)
    end)
    |> Enum.sort_by(& &1.due_date, {:asc, DateTime})
  end

  defp matches_deck?(_item, nil), do: true

  defp matches_deck?(item, deck_id) when is_integer(deck_id) do
    case item.word do
      %{id: word_id} ->
        case Repo.get_by(DeckWord, deck_id: deck_id, word_id: word_id) do
          nil -> false
          _ -> true
        end

      _ ->
        false
    end
  end

  defp find_item(items, item_id) do
    case Enum.find(items, &(&1.id == item_id)) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp replace_item(items, updated) do
    Enum.map(items, fn item ->
      if item.id == updated.id, do: updated, else: item
    end)
  end

  defp parse_quality(value) when is_binary(value) do
    value
    |> String.to_integer()
    |> FSRS.rating_from_quality()
  rescue
    ArgumentError -> :good
  end

  defp update_ratings(ratings, rating) do
    case rating do
      :again -> Map.update!(ratings, :again, &(&1 + 1))
      :hard -> Map.update!(ratings, :hard, &(&1 + 1))
      :good -> Map.update!(ratings, :good, &(&1 + 1))
      :easy -> Map.update!(ratings, :easy, &(&1 + 1))
    end
  end

  defp format_decimal(nil), do: "0.0×"
  defp format_decimal(value), do: "#{Float.round(value, 2)}×"

  defp interval_label(nil), do: "New"
  defp interval_label(0), do: "Learning"
  defp interval_label(days), do: "#{days}d"

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
end

defmodule LanglerWeb.StudyLive.Session do
  @moduledoc """
  Full-screen study session LiveView for focused card-by-card review.
  """

  use LanglerWeb, :live_view

  alias Langler.Study
  alias Langler.Study.FSRS

  @quality_buttons [
    %{score: 0, label: "Again", class: "btn-error"},
    %{score: 2, label: "Hard", class: "btn-warning"},
    %{score: 3, label: "Good", class: "btn-primary"},
    %{score: 4, label: "Easy", class: "btn-success"}
  ]

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    cards = load_due_today_cards(scope.user.id)

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
     |> assign(:quality_buttons, @quality_buttons)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div
        id="study-session-container"
        class="h-[calc(100vh-5rem)] flex flex-col overflow-hidden -mx-4 -my-10 sm:-mx-6 lg:-mx-8"
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
    </Layouts.app>
    """
  end

  defp render_study_session(assigns) do
    assigns = assign(assigns, :current_card, Enum.at(assigns.cards, assigns.current_index))

    ~H"""
    <div class="flex-1 flex items-center justify-center p-4 overflow-hidden min-h-0 px-4 py-4">
      <div class="w-full max-w-2xl h-full max-h-full flex flex-col min-h-0">
        <%!-- Exit button --%>
        <div class="flex justify-end mb-4">
          <.link
            id="study-session-exit"
            navigate={~p"/study"}
            class="btn btn-sm btn-ghost"
            aria-label="Exit study session"
          >
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </.link>
        </div>

        <%!-- Progress indicator --%>
        <div class="text-center mb-6">
          <p class="text-sm font-semibold text-base-content/70">
            Card {assigns.current_index + 1} of {assigns.total_cards}
          </p>
        </div>

        <%!-- Card container --%>
        <div
          id="study-card-container"
          class="study-card-container flex-1 min-h-0 flex items-center justify-center"
        >
          <%= if @current_card && @current_card.word do %>
            <div class="w-full h-full max-w-2xl min-h-[400px]">
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
    </div>
    """
  end

  defp render_card(assigns, item) do
    word = item.word
    definitions = word.definitions || []

    assigns =
      assign(assigns, :word, word) |> assign(:definitions, definitions) |> assign(:item, item)

    ~H"""
    <div
      id="study-card"
      class={[
        "swap swap-flip w-full h-full cursor-pointer",
        assigns.flipped && "swap-active"
      ]}
      phx-click="flip_card"
    >
      <%!-- Front side (swap-off) - Word, Stats, Rating --%>
      <div class="swap-off w-full h-full">
        <div class="card bg-base-100 shadow-xl h-full w-full flex flex-col">
          <div class="card-body gap-4 overflow-y-auto flex-1 min-h-0">
            <%!-- Word --%>
            <div class="flex flex-col items-center justify-center gap-4 flex-1 min-h-0">
              <p class="text-4xl font-semibold text-base-content text-center">
                {@word.lemma || @word.normalized_form}
              </p>
              <p class="text-sm text-base-content/70">
                Click or press spacebar to see definition
              </p>
            </div>

            <div class="divider my-2"></div>

            <%!-- Stats --%>
            <div class="flex flex-wrap gap-6 text-sm text-base-content/70">
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

            <div class="divider my-2"></div>

            <%!-- Rating buttons --%>
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
                  phx-click="rate_card"
                  phx-value-item-id={@item.id}
                  phx-value-quality={button.score}
                  phx-stop-propagation
                >
                  {button.label}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Back side (swap-on) - Definition only --%>
      <div class="swap-on w-full h-full">
        <div class="card bg-base-100 shadow-xl h-full w-full flex flex-col">
          <div class="card-body gap-4 overflow-y-auto flex-1 min-h-0 flex flex-col items-center justify-center">
            <div class="flex flex-col gap-2 w-full">
              <p class="text-xs font-semibold uppercase tracking-widest text-base-content/60">
                Definition
              </p>
              <%= if @definitions != [] do %>
                <ol class="space-y-2 text-sm leading-relaxed text-base-content/90">
                  <li :for={{definition, idx} <- Enum.with_index(@definitions, 1)} class="break-words">
                    <span class="font-semibold text-primary/80">{idx}.</span>
                    <span class="ml-2 break-words">{definition}</span>
                  </li>
                </ol>
              <% else %>
                <p class="text-sm text-base-content/70">No definition available</p>
              <% end %>
            </div>
          </div>
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
    <div id="study-session-complete" class="flex-1 flex items-center justify-center p-4">
      <div class="card bg-base-100 shadow-xl max-w-2xl w-full">
        <div class="card-body gap-6">
          <div class="text-center">
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

          <div class="flex gap-3 justify-center">
            <.link navigate={~p"/study"} class="btn btn-primary text-white">
              Return to Study Overview
            </.link>
            <.link navigate={~p"/study/session"} class="btn btn-outline">
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
        %{"quality" => quality} = params,
        socket
      ) do
    item_id_str = params["item_id"] || params["item-id"]

    if item_id_str do
      item_id = String.to_integer(item_id_str)
      current_card = Enum.at(socket.assigns.cards, socket.assigns.current_index)

      if current_card && current_card.id == item_id do
        with {:ok, item} <- find_item(socket.assigns.cards, item_id),
             rating <- parse_quality(quality),
             {:ok, updated} <- Study.review_item(item, rating) do
          # Update the card in the list
          updated_cards = replace_item(socket.assigns.cards, updated)

          # Update ratings distribution
          ratings = update_ratings(socket.assigns.ratings, rating)

          # Advance to next card or complete
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
            {:noreply, put_flash(socket, :error, "Unable to rate card: #{inspect(reason)}")}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_due_today_cards(user_id) do
    now = DateTime.utc_now()
    end_of_day = end_of_day(now)

    Study.list_items_for_user(user_id)
    |> Enum.filter(fn item -> due_today?(item, end_of_day) and not is_nil(item.word) end)
    |> Enum.sort_by(& &1.due_date, {:asc, DateTime})
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

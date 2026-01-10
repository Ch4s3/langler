defmodule LanglerWeb.StudyLive.Index do
  use LanglerWeb, :live_view

  alias Langler.Study
  alias Langler.Study.FSRS

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

    {:ok,
     socket
     |> assign(:current_user, scope.user)
     |> assign(:filters, @filters)
     |> assign(:filter, filter)
     |> assign(:quality_buttons, @quality_buttons)
     |> assign(:stats, build_stats(items))
     |> assign(:all_items, items)
     |> stream(:items, visible_items)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl space-y-8 py-8">
        <div class="card border border-base-200 bg-base-100/90 shadow-2xl backdrop-blur">
          <div class="card-body gap-6">
            <div class="flex flex-col gap-2">
              <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                Study overview
              </p>
              <h1 class="text-3xl font-bold text-base-content">Stay consistent with your deck</h1>
              <p class="text-sm text-base-content/70">
                Track upcoming reviews and keep tabs on due cards with quick filters.
              </p>
            </div>

            <div class="grid gap-4 sm:grid-cols-3">
              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow">
                <div class="stat-title text-base-content/60">Due now</div>
                <div class="stat-value text-4xl text-primary">{@stats.due_now}</div>
                <div class="stat-desc text-base-content/70">Ready for immediate review</div>
              </div>

              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow">
                <div class="stat-title text-base-content/60">Due today</div>
                <div class="stat-value text-4xl text-secondary">{@stats.due_today}</div>
                <div class="stat-desc text-base-content/70">
                  Includes overdue &amp; later today
                </div>
              </div>

              <div class="stat rounded-2xl border border-base-200 bg-base-100 shadow">
                <div class="stat-title text-base-content/60">Total tracked</div>
                <div class="stat-value text-4xl text-base-content">{@stats.total}</div>
                <div class="stat-desc text-base-content/70">Words in your study bank</div>
              </div>
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
            </div>

            <div
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              class="card border border-base-200 bg-base-100/95 shadow-xl backdrop-blur"
            >
              <div class="card-body gap-5">
                <div class="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <p class="text-2xl font-semibold text-base-content">
                      {item.word && (item.word.lemma || item.word.normalized_form)}
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
                </div>

                <div class="flex flex-col gap-2">
                  <p class="text-xs font-semibold uppercase tracking-widest text-base-content/60">
                    Rate this card
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <button
                      :for={button <- @quality_buttons}
                      type="button"
                      class={["btn btn-sm font-semibold text-white", button.class]}
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
    visible = filter_items(socket.assigns.all_items, filter)

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
      visible = filter_items(all_items, socket.assigns.filter)

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

  defp filter_items(items, filter) do
    now = DateTime.utc_now()
    end_of_day = end_of_day(now)

    Enum.filter(items, fn item ->
      case filter do
        :now -> due_now?(item, now)
        :today -> due_today?(item, end_of_day)
        :all -> true
      end
    end)
  end

  defp build_stats(items) do
    now = DateTime.utc_now()
    end_of_day = end_of_day(now)

    %{
      due_now: Enum.count(items, &due_now?(&1, now)),
      due_today: Enum.count(items, &due_today?(&1, end_of_day)),
      total: length(items)
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
end

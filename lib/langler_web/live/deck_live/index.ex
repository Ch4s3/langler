defmodule LanglerWeb.DeckLive.Index do
  @moduledoc """
  LiveView for deck management: CRUD, follow/share, LLM suggestions, drag-and-drop.
  """

  use LanglerWeb, :live_view

  alias Langler.Vocabulary
  alias Langler.Vocabulary.DeckSuggester
  alias Langler.Vocabulary.Decks
  alias LanglerWeb.DeckComponents

  import LanglerWeb.DeckComponents

  @tabs [
    %{id: :my_decks, label: "My Decks"},
    %{id: :following, label: "Following"},
    %{id: :shared, label: "Shared with me"},
    %{id: :discover, label: "Discover"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id
    deck_data = load_deck_data(user_id)

    {:ok,
     socket
     |> assign(:tabs, @tabs)
     |> assign(:active_tab, :my_decks)
     |> assign(:my_decks, deck_data.my_decks)
     |> assign(:followed_decks, deck_data.followed_decks)
     |> assign(:shared_decks, deck_data.shared_decks)
     |> assign(:public_decks, deck_data.public_decks)
     |> assign(:ungrouped_count, deck_data.ungrouped_count)
     |> assign(:expanded_deck_ids, MapSet.new())
     |> assign(:deck_contents_by_id, %{})
     |> assign(:show_deck_modal, false)
     |> assign(:editing_deck_id, nil)
     |> assign(:editing_deck, nil)
     |> assign(
       :deck_form,
       to_form(%{"name" => "", "description" => "", "visibility" => "private"})
     )
     |> assign(:show_suggestions_panel, false)
     |> assign(:suggestions, [])
     |> assign(:suggestions_loading, false)
     |> assign(:suggestions_error, nil)
     |> assign(:expanded_suggestion_index, nil)
     |> assign(:show_custom_card_modal, false)
     |> assign(:custom_card_form, to_form(%{"front" => "", "back" => "", "language" => "es"}))
     |> assign(:custom_card_deck_ids, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl space-y-6 p-4">
        <.header>
          Decks
          <:subtitle>Organize your vocabulary into focused study collections</:subtitle>
        </.header>

        <%!-- Tabs --%>
        <div role="tablist" class="tabs tabs-boxed bg-base-200/50 p-1 rounded-lg">
          <button
            :for={tab <- @tabs}
            type="button"
            role="tab"
            class={["tab", @active_tab == tab.id && "tab-active"]}
            phx-click="set_tab"
            phx-value-tab={tab.id}
          >
            {tab.label}
          </button>
        </div>

        <%!-- Content by tab --%>
        <div class="mt-6">
          <%= cond do %>
            <% @active_tab == :my_decks -> %>
              <.my_decks_content
                my_decks={@my_decks}
                ungrouped_count={@ungrouped_count}
                expanded_deck_ids={@expanded_deck_ids}
                deck_contents_by_id={@deck_contents_by_id}
                current_user_id={@current_scope.user.id}
                suggestions_loading={@suggestions_loading}
                suggestions_error={@suggestions_error}
                show_suggestions_panel={@show_suggestions_panel}
                suggestions={@suggestions}
                expanded_suggestion_index={@expanded_suggestion_index}
              />
            <% @active_tab == :following -> %>
              <.following_content
                followed_decks={@followed_decks}
                expanded_deck_ids={@expanded_deck_ids}
                deck_contents_by_id={@deck_contents_by_id}
              />
            <% @active_tab == :shared -> %>
              <.shared_content
                shared_decks={@shared_decks}
                expanded_deck_ids={@expanded_deck_ids}
                deck_contents_by_id={@deck_contents_by_id}
              />
            <% @active_tab == :discover -> %>
              <.discover_content public_decks={@public_decks} />
            <% true -> %>
              <p class="text-base-content/60">Select a tab</p>
          <% end %>
        </div>
      </div>

      <%!-- Deck create/edit modal --%>
      <DeckComponents.deck_modal
        show={@show_deck_modal}
        editing_deck={@editing_deck}
        form={@deck_form}
      />
    </Layouts.app>
    """
  end

  defp my_decks_content(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Ungrouped words banner + AI suggestions --%>
      <div :if={@ungrouped_count > 0} class="card border border-base-200 bg-base-100">
        <div class="card-body py-4">
          <p class="text-sm text-base-content/80">
            💡 {@ungrouped_count} words in your default deck are not in any other deck.
          </p>
          <p class="text-xs text-base-content/60 mt-1">
            Get AI suggestions to group them by theme, grammar, or difficulty.
          </p>
          <div :if={@suggestions_error} class="alert alert-error mt-2 text-sm">
            {@suggestions_error}
          </div>
          <button
            type="button"
            class="btn btn-primary btn-sm mt-2"
            phx-click="request_llm_suggestions"
            phx-disable-with="Analyzing…"
            disabled={@suggestions_loading}
          >
            <%= if @suggestions_loading do %>
              <span class="loading loading-spinner loading-sm"></span> Analyzing…
            <% else %>
              Get AI Suggestions
            <% end %>
          </button>
        </div>
      </div>

      <%!-- AI Suggestions panel --%>
      <div
        :if={@show_suggestions_panel and @suggestions != []}
        class="card border border-primary/30 bg-base-100"
      >
        <div class="card-body">
          <div class="flex items-center justify-between mb-2">
            <h3 class="font-semibold">AI Deck Suggestions</h3>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="close_suggestions_panel"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" /> Close
            </button>
          </div>
          <p class="text-sm text-base-content/60 mb-4">
            We found {length(@suggestions)} potential grouping(s). Create a deck from a suggestion or dismiss it.
          </p>
          <div class="space-y-3">
            <.suggestion_card
              :for={{suggestion, index} <- Enum.with_index(@suggestions)}
              suggestion={suggestion}
              index={index}
              expanded={@expanded_suggestion_index == index}
            />
          </div>
        </div>
      </div>

      <%!-- Deck cards --%>
      <div class="space-y-3">
        <div
          :for={deck <- @my_decks}
          id={"deck-card-#{deck.id}"}
        >
          <.deck_card
            deck={deck}
            variant={:owned}
            expanded={MapSet.member?(@expanded_deck_ids, deck.id)}
            words={get_in(@deck_contents_by_id, [deck.id, :words]) || []}
            custom_cards={get_in(@deck_contents_by_id, [deck.id, :custom_cards]) || []}
            word_count={deck.word_count || 0}
          />
        </div>
      </div>

      <%!-- Create deck button --%>
      <button
        type="button"
        class="btn btn-outline btn-block"
        phx-click="open_new_deck_modal"
      >
        + Create New Deck
      </button>
    </div>
    """
  end

  defp following_content(assigns) do
    ~H"""
    <div class="space-y-3">
      <p :if={@followed_decks == []} class="text-base-content/60">
        You are not following any public decks. Use Discover to find decks to follow.
      </p>
      <div :for={item <- @followed_decks} id={"followed-#{item.deck.id}"}>
        <.deck_card
          deck={item.deck}
          variant={:followed}
          expanded={MapSet.member?(@expanded_deck_ids, item.deck.id)}
          words={get_in(@deck_contents_by_id, [item.deck.id, :words]) || []}
          custom_cards={get_in(@deck_contents_by_id, [item.deck.id, :custom_cards]) || []}
          word_count={deck_word_count(item)}
          owner={item.owner}
          follower_count={item.follower_count || 0}
        />
      </div>
    </div>
    """
  end

  defp shared_content(assigns) do
    ~H"""
    <div class="space-y-3">
      <p :if={@shared_decks == []} class="text-base-content/60">
        No decks have been shared with you yet.
      </p>
      <div :for={item <- @shared_decks} id={"shared-#{item.deck.id}"}>
        <.deck_card
          deck={item.deck}
          variant={:shared}
          expanded={MapSet.member?(@expanded_deck_ids, item.deck.id)}
          words={get_in(@deck_contents_by_id, [item.deck.id, :words]) || []}
          custom_cards={get_in(@deck_contents_by_id, [item.deck.id, :custom_cards]) || []}
          word_count={deck_word_count(item)}
          owner={item.owner}
        />
      </div>
    </div>
    """
  end

  defp discover_content(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-base-content/60 mb-4">Browse public decks to follow or copy.</p>
      <div :for={item <- @public_decks} id={"discover-#{item.deck.id}"}>
        <.deck_card
          deck={item.deck}
          variant={:discover}
          expanded={false}
          words={[]}
          custom_cards={[]}
          word_count={0}
          owner={item.owner}
          follower_count={item.follower_count || 0}
        />
      </div>
    </div>
    """
  end

  defp deck_word_count(%{deck: _deck, follower_count: _}), do: 0
  defp deck_word_count(_), do: 0

  ## Events

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, assign(socket, :active_tab, tab_atom)}
  end

  @impl true
  def handle_event("toggle_deck_expanded", %{"deck-id" => deck_id_str}, socket) do
    deck_id = String.to_integer(deck_id_str)
    user_id = socket.assigns.current_scope.user.id
    expanded = MapSet.member?(socket.assigns.expanded_deck_ids, deck_id)

    new_expanded =
      if expanded do
        MapSet.delete(socket.assigns.expanded_deck_ids, deck_id)
      else
        MapSet.put(socket.assigns.expanded_deck_ids, deck_id)
      end

    socket =
      socket
      |> assign(:expanded_deck_ids, new_expanded)
      |> then(fn s ->
        if not expanded do
          load_deck_contents(s, deck_id, user_id)
        else
          s
        end
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_default_deck", %{"deck-id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id
    deck_id = String.to_integer(deck_id_str)

    case Vocabulary.set_default_deck(user_id, deck_id) do
      {:ok, _} ->
        deck_data = load_deck_data(user_id)

        {:noreply,
         socket
         |> assign(:my_decks, deck_data.my_decks)
         |> put_flash(:info, "Default deck updated.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not set default deck.")}
    end
  end

  @impl true
  def handle_event("edit_deck", %{"deck-id" => deck_id_str}, socket) do
    deck_id = String.to_integer(deck_id_str)
    deck = find_deck_in_assigns(socket.assigns.my_decks, deck_id)

    if deck do
      form_params = %{
        "name" => deck.name || "",
        "description" => deck.description || "",
        "visibility" => deck.visibility || "private"
      }

      {:noreply,
       socket
       |> assign(:show_deck_modal, true)
       |> assign(:editing_deck_id, deck_id)
       |> assign(:editing_deck, deck)
       |> assign(:deck_form, to_form(form_params))}
    else
      {:noreply, put_flash(socket, :error, "Deck not found.")}
    end
  end

  @impl true
  def handle_event("set_visibility", %{"deck-id" => deck_id_str}, socket) do
    # Reuse edit modal so user can change visibility (and optionally name/description)
    handle_event("edit_deck", %{"deck-id" => deck_id_str}, socket)
  end

  @impl true
  def handle_event("delete_deck", %{"deck-id" => deck_id_str}, socket) do
    user_id = socket.assigns.current_scope.user.id
    deck_id = String.to_integer(deck_id_str)

    case Vocabulary.delete_deck(deck_id, user_id) do
      {:ok, _deck} ->
        deck_data = load_deck_data(user_id)

        {:noreply,
         socket
         |> assign(:my_decks, deck_data.my_decks)
         |> assign(:ungrouped_count, deck_data.ungrouped_count)
         |> put_flash(:info, "Deck deleted. Cards remain in your study bank.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Deck not found.")}

      {:error, :cannot_delete_default} ->
        {:noreply, put_flash(socket, :error, "Cannot delete the default deck.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete deck.")}
    end
  end

  @impl true
  def handle_event("request_llm_suggestions", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      socket
      |> assign(:suggestions_loading, true)
      |> assign(:suggestions_error, nil)
      |> start_async(:fetch_suggestions, fn ->
        DeckSuggester.suggest_groupings(user_id)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_suggestions_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_suggestions_panel, false)
     |> assign(:expanded_suggestion_index, nil)}
  end

  @impl true
  def handle_event("toggle_suggestion_expanded", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    current = socket.assigns.expanded_suggestion_index
    new_expanded = if current == index, do: nil, else: index
    {:noreply, assign(socket, :expanded_suggestion_index, new_expanded)}
  end

  @impl true
  def handle_event("accept_suggestion", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    suggestion = Enum.at(socket.assigns.suggestions, index)
    user_id = socket.assigns.current_scope.user.id

    deck_attrs = %{
      name: suggestion.name,
      description: suggestion.description || ""
    }

    case Decks.create_deck_with_words(user_id, deck_attrs, suggestion.word_ids) do
      {:ok, _deck} ->
        deck_data = load_deck_data(user_id)
        remaining = List.delete_at(socket.assigns.suggestions, index)

        {:noreply,
         socket
         |> assign(:suggestions, remaining)
         |> assign(:my_decks, deck_data.my_decks)
         |> assign(:ungrouped_count, deck_data.ungrouped_count)
         |> put_flash(:info, "Deck created.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create deck.")}
    end
  end

  @impl true
  def handle_event("dismiss_suggestion", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    remaining = List.delete_at(socket.assigns.suggestions, index)
    {:noreply, assign(socket, :suggestions, remaining)}
  end

  @impl true
  def handle_event("open_new_deck_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_deck_modal, true)
     |> assign(:editing_deck_id, nil)
     |> assign(:editing_deck, nil)
     |> assign(
       :deck_form,
       to_form(%{"name" => "", "description" => "", "visibility" => "private"})
     )}
  end

  @impl true
  def handle_event("hide_deck_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_deck_modal, false)
     |> assign(:editing_deck_id, nil)
     |> assign(:editing_deck, nil)}
  end

  @impl true
  def handle_event("validate_deck", params, socket) do
    # Params may be flat or under "deck" from the form
    p = params["deck"] || params

    attrs = %{
      "name" => p["name"] || "",
      "description" => p["description"] || "",
      "visibility" => p["visibility"] || "private"
    }

    form = to_form(attrs)

    {:noreply, assign(socket, :deck_form, form)}
  end

  @impl true
  def handle_event("create_deck", params, socket) do
    user_id = socket.assigns.current_scope.user.id
    p = params["deck"] || params
    name = (p["name"] || "") |> String.trim()

    attrs = %{
      "name" => name,
      "description" =>
        (p["description"] || "") |> String.trim() |> then(&if(&1 == "", do: nil, else: &1)),
      "visibility" => p["visibility"] || "private"
    }

    case Vocabulary.create_deck(user_id, attrs) do
      {:ok, _deck} ->
        deck_data = load_deck_data(user_id)

        {:noreply,
         socket
         |> assign(:show_deck_modal, false)
         |> assign(:editing_deck_id, nil)
         |> assign(:editing_deck, nil)
         |> assign(:my_decks, deck_data.my_decks)
         |> assign(:ungrouped_count, deck_data.ungrouped_count)
         |> put_flash(:info, "Deck created.")}

      {:error, changeset} ->
        form = to_form(changeset)
        {:noreply, assign(socket, :deck_form, form)}
    end
  end

  @impl true
  def handle_event("update_deck", params, socket) do
    user_id = socket.assigns.current_scope.user.id
    p = params["deck"] || params
    deck_id_str = p["deck_id"] || params["deck_id"]

    if blank?(deck_id_str) do
      {:noreply, put_flash(socket, :error, "Missing deck.")}
    else
      deck_id = String.to_integer(deck_id_str)

      attrs = %{
        "name" => (p["name"] || "") |> String.trim(),
        "description" =>
          (p["description"] || "") |> String.trim() |> then(&if(&1 == "", do: nil, else: &1)),
        "visibility" => p["visibility"] || "private"
      }

      case Vocabulary.update_deck(deck_id, user_id, attrs) do
        {:ok, _deck} ->
          deck_data = load_deck_data(user_id)

          {:noreply,
           socket
           |> assign(:show_deck_modal, false)
           |> assign(:editing_deck_id, nil)
           |> assign(:editing_deck, nil)
           |> assign(:my_decks, deck_data.my_decks)
           |> put_flash(:info, "Deck updated.")}

        {:error, :not_found} ->
          {:noreply,
           socket
           |> assign(:show_deck_modal, false)
           |> put_flash(:error, "Deck not found.")}

        {:error, changeset} ->
          form = to_form(changeset)
          {:noreply, assign(socket, :deck_form, form)}
      end
    end
  end

  ## Async callbacks

  @impl true
  def handle_async(:fetch_suggestions, {:ok, {:ok, suggestions}}, socket) do
    {:noreply,
     socket
     |> assign(:suggestions_loading, false)
     |> assign(:suggestions, suggestions)
     |> assign(:show_suggestions_panel, true)}
  end

  @impl true
  def handle_async(:fetch_suggestions, {:ok, {:error, :no_ungrouped_words}}, socket) do
    {:noreply,
     socket
     |> assign(:suggestions_loading, false)
     |> put_flash(:info, "All your words are already organized into decks.")}
  end

  @impl true
  def handle_async(:fetch_suggestions, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:suggestions_loading, false)
     |> assign(:suggestions_error, format_suggestion_error(reason))}
  end

  @impl true
  def handle_async(:fetch_suggestions, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:suggestions_loading, false)
     |> assign(:suggestions_error, "Request failed. Please try again.")}
  end

  ## Private

  defp load_deck_data(user_id) do
    my_decks = Decks.list_decks_with_words(user_id)
    followed_decks = Decks.list_followed_decks(user_id)
    shared_decks = Decks.list_shared_decks_for_user(user_id)
    public_decks = Decks.list_public_decks(limit: 20)
    ungrouped_words = Vocabulary.list_ungrouped_words(user_id)

    %{
      my_decks: my_decks,
      followed_decks: followed_decks,
      shared_decks: shared_decks,
      public_decks: public_decks,
      ungrouped_count: length(ungrouped_words)
    }
  end

  defp load_deck_contents(socket, deck_id, user_id) do
    words = Decks.list_deck_words(deck_id, user_id)
    custom_cards = Decks.list_deck_custom_cards(deck_id, user_id)

    new_contents =
      Map.put(socket.assigns.deck_contents_by_id, deck_id, %{
        words: words,
        custom_cards: custom_cards
      })

    assign(socket, :deck_contents_by_id, new_contents)
  end

  defp format_suggestion_error(:no_llm_config),
    do: "Configure an LLM in settings to use suggestions."

  defp format_suggestion_error(:no_ungrouped_words), do: "No ungrouped words to suggest from."

  defp format_suggestion_error({:too_few_words, n}),
    do: "Add at least 10 ungrouped words (you have #{n})."

  defp format_suggestion_error(:invalid_format),
    do: "AI returned an unexpected format. Try again."

  defp format_suggestion_error(:invalid_json), do: "Could not read AI response. Try again."
  defp format_suggestion_error(other), do: "Suggestions failed: #{inspect(other)}"

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false

  defp find_deck_in_assigns(my_decks, deck_id) when is_list(my_decks) do
    Enum.find(my_decks, fn d -> d.id == deck_id end)
  end
end

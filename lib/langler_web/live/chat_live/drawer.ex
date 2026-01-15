defmodule LanglerWeb.ChatLive.Drawer do
  @moduledoc """
  LiveComponent for the chat drawer interface.
  Renders in the bottom-right corner of the screen as a slide-out drawer.
  """
  use LanglerWeb, :live_component

  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Session
  alias Langler.LLM.Adapters.ChatGPT
  alias Langler.Study
  alias Langler.External.Dictionary
  alias Langler.Vocabulary

  require Logger
  import Phoenix.HTML

  @token_regex ~r/\p{L}+\p{M}*|[^\p{L}]+/u

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:chat_open, fn -> false end)
      |> assign_new(:sidebar_open, fn -> false end)
      |> assign_new(:keyboard_open, fn -> false end)
      |> assign_new(:current_session, fn -> nil end)
      |> assign_new(:sessions, fn -> [] end)
      |> assign_new(:session_search, fn -> "" end)
      |> assign_new(:input_value, fn -> "" end)
      |> assign_new(:sending, fn -> false end)
      |> assign_new(:total_tokens, fn -> 0 end)
      |> assign_new(:messages, fn -> [] end)
      |> assign_new(:studied_word_ids, fn -> MapSet.new() end)
      |> assign_new(:studied_forms, fn -> MapSet.new() end)
      |> assign_new(:llm_config_missing, fn -> false end)
      |> maybe_stream_messages()

    # Handle async updates from background task
    socket =
      case Map.get(assigns, :action) do
        :add_assistant_message ->
          dom_id =
            case assigns.message.inserted_at do
              %DateTime{} = dt -> "msg-#{DateTime.to_unix(dt)}"
              _ -> "msg-#{System.unique_integer([:positive])}"
            end

          socket
          |> stream_insert(:messages, assigns.message, dom_id: dom_id)
          |> assign(:sending, false)
          |> assign(:total_tokens, socket.assigns.total_tokens + assigns.tokens)

        :start_article_chat ->
          handle_start_article_chat(socket, assigns)

        :sending_complete ->
          assign(socket, :sending, false)

        _ ->
          socket
      end

    {:ok, socket}
  end

  defp maybe_stream_messages(socket) do
    messages = socket.assigns.messages || []

    dom_id_fn = fn msg ->
      case msg.inserted_at do
        %DateTime{} = dt -> "msg-#{DateTime.to_unix(dt)}"
        _ -> "msg-#{System.unique_integer([:positive])}"
      end
    end

    if is_list(messages) and length(messages) > 0 do
      stream(socket, :messages, messages, dom_id: dom_id_fn)
    else
      stream(socket, :messages, [], dom_id: dom_id_fn)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chat-drawer-container" phx-component="chat-drawer" class="fixed bottom-0 right-0 z-50">
      <%!-- Floating Chat Button --%>
      <button
        :if={!@chat_open}
        type="button"
        phx-click="toggle_chat"
        phx-target={@myself}
        class="btn btn-circle btn-primary btn-lg fixed bottom-6 right-6 shadow-2xl transition-all duration-300 hover:scale-110 hover:shadow-primary/50"
        aria-label="Open chat"
      >
        <.icon name="hero-chat-bubble-left-right" class="h-7 w-7 text-white" />
      </button>

      <%!-- Chat Drawer --%>
      <div
        class={[
          "fixed inset-0 z-50 flex bg-base-100 transition-transform duration-300 ease-in-out",
          @chat_open && "translate-x-0 opacity-100",
          !@chat_open && "translate-x-full opacity-0 pointer-events-none"
        ]}
        aria-hidden={!@chat_open}
      >
        <%!-- Sidebar --%>
        <div class={[
          "flex flex-col border-r border-base-200 bg-base-200/50 transition-all duration-300",
          if(@sidebar_open, do: "w-64", else: "w-0 overflow-hidden")
        ]}>
          <div class="flex h-full flex-col">
            <%!-- New Chat Button --%>
            <button
              type="button"
              phx-click="new_session"
              phx-target={@myself}
              class="m-2 btn btn-primary btn-sm gap-2"
            >
              <.icon name="hero-plus" class="h-4 w-4" />
              <span :if={@sidebar_open}>New Chat</span>
            </button>

            <%!-- Search Input --%>
            <div :if={@sidebar_open} class="px-2 mb-2">
              <div class="relative">
                <.icon
                  name="hero-magnifying-glass"
                  class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-base-content/40"
                />
                <input
                  type="text"
                  phx-input="search_sessions"
                  phx-target={@myself}
                  value={@session_search}
                  placeholder="Search chats..."
                  class="input input-sm input-bordered w-full pl-9"
                />
              </div>
            </div>

            <%!-- Chat List --%>
            <div :if={@sidebar_open} class="flex-1 px-2">
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/60 px-2 py-1 mb-1">
                Your Chats
              </div>
              <div class="space-y-1 max-h-[calc(100vh-14rem)] overflow-y-auto pr-1">
                <div
                  :for={session <- filtered_sessions(@sessions, @session_search)}
                  class={[
                    "group flex items-start gap-2 rounded-lg border border-base-300/70 bg-base-100 px-3 py-3 transition-all relative",
                    if(@current_session && session.id == @current_session.id,
                      do: "border-primary/50 bg-primary/5 shadow-sm",
                      else: "hover:border-base-400"
                    )
                  ]}
                >
                  <button
                    type="button"
                    phx-click="switch_session"
                    phx-value-session-id={session.id}
                    phx-target={@myself}
                    class="flex-1 text-left"
                  >
                    <p class="text-sm font-semibold text-base-content truncate">
                      {session.title || "Untitled Chat"}
                    </p>
                    <p class="text-xs text-base-content/60">{format_date(session.inserted_at)}</p>
                  </button>
                  <button
                    type="button"
                    phx-click="delete_session"
                    phx-value-session-id={session.id}
                    phx-target={@myself}
                    class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity absolute top-2 right-2"
                    aria-label="Delete chat"
                  >
                    <.icon name="hero-trash" class="h-4 w-4 text-error" />
                  </button>
                </div>
              </div>
              <div
                :if={filtered_sessions(@sessions, @session_search) == []}
                class="px-3 py-4 text-sm text-base-content/60 text-center"
              >
                No chats found
              </div>
            </div>
          </div>
        </div>

        <%!-- Main Chat Area --%>
        <div class="flex-1 flex flex-col min-w-0">
          <%!-- Header --%>
          <div class="flex items-center justify-between border-b border-base-200 bg-base-200/50 px-4 py-3">
            <div class="flex items-center gap-3">
              <button
                type="button"
                phx-click="toggle_sidebar"
                phx-target={@myself}
                class="btn btn-ghost btn-sm btn-square"
                aria-label="Toggle sidebar"
              >
                <.icon name="hero-bars-3" class="h-5 w-5" />
              </button>
              <div class="flex items-center gap-2">
                <.icon name="hero-chat-bubble-left-right" class="h-5 w-5 text-primary" />
                <h3 class="text-lg font-semibold text-base-content">
                  {if @current_session,
                    do: @current_session.title || "New Chat",
                    else: "Chat Assistant"}
                </h3>
              </div>
            </div>
            <button
              type="button"
              phx-click="toggle_chat"
              phx-target={@myself}
              class="btn btn-circle btn-ghost btn-sm"
              aria-label="Close chat"
            >
              <.icon name="hero-x-mark" class="h-5 w-5" />
            </button>
          </div>

          <%!-- Messages Area --%>
          <div class="flex-1 overflow-y-auto p-4">
            <%= if @current_session == nil do %>
              <div class="flex h-full flex-col items-center justify-center gap-4 text-center">
                <.icon name="hero-chat-bubble-left-right" class="h-16 w-16 text-base-content/20" />
                <div>
                  <h4 class="text-lg font-semibold text-base-content">Start a conversation</h4>
                  <p class="text-sm text-base-content/60">
                    Practice your target language with AI assistance
                  </p>
                </div>

                <%= if @llm_config_missing do %>
                  <div class="alert alert-warning max-w-md">
                    <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
                    <div class="text-left">
                      <p class="font-semibold">LLM Configuration Required</p>
                      <p class="text-sm">
                        Please configure your LLM provider in
                        <.link navigate={~p"/users/settings/llm"} class="link">settings</.link>
                        to start chatting.
                      </p>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="space-y-4" id="chat-messages" phx-update="stream">
                <div
                  :for={{id, msg} <- @streams.messages}
                  :if={msg.role in ["user", "assistant"]}
                  id={id}
                  class={[
                    "chat",
                    msg.role == "user" && "chat-end",
                    msg.role != "user" && "chat-start"
                  ]}
                >
                  <div class="chat-bubble">
                    <%= if msg.role == "assistant" && @current_session do %>
                      <div class="markdown-content prose prose-sm max-w-none dark:prose-invert">
                        {raw(
                          add_word_tooltips(
                            render_markdown(msg.content),
                            @current_session.target_language,
                            @studied_word_ids,
                            @studied_forms,
                            id,
                            @myself.cid
                          )
                        )}
                      </div>
                    <% else %>
                      {msg.content}
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Input Area --%>
          <div class="border-t border-base-200 bg-base-200/50">
            <%!-- Special Characters Keyboard --%>
            <div
              :if={@keyboard_open && @current_session}
              class="border-b border-base-200 bg-base-100 p-3"
            >
              <div class="flex items-center justify-between mb-2">
                <span class="text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                  Special Characters
                </span>
                <button
                  type="button"
                  phx-click="toggle_keyboard"
                  phx-target={@myself}
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label="Hide keyboard"
                >
                  <.icon name="hero-chevron-down" class="h-4 w-4" />
                </button>
              </div>
              <div class="flex flex-wrap gap-1.5 justify-center">
                <button
                  :for={char <- get_special_chars(@current_session.target_language)}
                  type="button"
                  phx-click="insert_char"
                  phx-value-char={char}
                  phx-target={@myself}
                  class="kbd kbd-sm hover:bg-primary hover:text-primary-content transition-colors cursor-pointer"
                >
                  {char}
                </button>
              </div>
            </div>
            <div :if={!@keyboard_open && @current_session} class="px-4 pt-2">
              <button
                type="button"
                phx-click="toggle_keyboard"
                phx-target={@myself}
                class="btn btn-ghost btn-xs gap-1"
                aria-label="Show keyboard"
              >
                <.icon name="hero-chevron-up" class="h-4 w-4" />
                <span class="text-xs">Special Characters</span>
              </button>
            </div>
            <div class="p-4">
              <form phx-submit="send_message" phx-target={@myself} class="flex gap-2">
                <input
                  type="text"
                  name="message"
                  value={@input_value}
                  phx-change="update_input"
                  phx-target={@myself}
                  placeholder="Type your message..."
                  class="input input-bordered flex-1"
                  autocomplete="off"
                  autocorrect="off"
                  autocapitalize="off"
                  spellcheck="false"
                  disabled={@llm_config_missing || @sending}
                />
                <button
                  type="submit"
                  class="btn btn-primary"
                  disabled={@llm_config_missing || @input_value == "" || @sending}
                >
                  <%= if @sending do %>
                    <span class="loading loading-spinner loading-sm"></span>
                  <% else %>
                    <.icon name="hero-paper-airplane" class="h-5 w-5" />
                  <% end %>
                </button>
              </form>

              <%!-- Token count display --%>
              <div :if={@current_session} class="mt-2 text-right">
                <span class="text-xs text-base-content/40">{@total_tokens} tokens</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    chat_open = !socket.assigns.chat_open

    socket =
      if chat_open do
        # Check if user has LLM config when opening
        user = socket.assigns.current_scope.user
        default_config = LlmConfig.get_default_config(user.id)

        # Load all sessions for the user
        sessions = Session.list_user_sessions(user.id, limit: 20)
        current_session = List.first(sessions)

        # Load studied words for the user
        {studied_word_ids, studied_forms} = load_studied_words(user.id)

        socket =
          socket
          |> assign(:chat_open, true)
          |> assign(:sessions, sessions)
          |> assign(:sidebar_open, false)
          |> assign(:session_search, "")
          |> assign(:studied_word_ids, studied_word_ids)
          |> assign(:studied_forms, studied_forms)
          |> assign(:llm_config_missing, is_nil(default_config))

        # Load messages if session exists
        if current_session do
          messages = Session.get_decrypted_messages(current_session)
          total_tokens = Enum.reduce(messages, 0, fn msg, acc -> acc + (msg.token_count || 0) end)

          socket
          |> assign(:current_session, current_session)
          |> assign(:total_tokens, total_tokens)
          |> stream(:messages, messages,
            reset: true,
            dom_id: fn msg ->
              "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
            end
          )
        else
          socket
          |> assign(:current_session, nil)
          |> assign(:total_tokens, 0)
          |> stream(:messages, [],
            reset: true,
            dom_id: fn _msg -> "msg-#{System.unique_integer([:positive])}" end
          )
        end
      else
        assign(socket, :chat_open, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("search_sessions", %{"value" => search}, socket) do
    {:noreply, assign(socket, :session_search, search)}
  end

  @impl true
  def handle_event("toggle_keyboard", _params, socket) do
    {:noreply, assign(socket, :keyboard_open, !socket.assigns.keyboard_open)}
  end

  @impl true
  def handle_event("insert_char", %{"char" => char}, socket) do
    current_input = socket.assigns.input_value || ""
    new_input = current_input <> char
    {:noreply, assign(socket, :input_value, new_input)}
  end

  @impl true
  def handle_event(
        "fetch_word_data",
        %{
          "word" => word,
          "language" => language,
          "dom_id" => dom_id
        } = params,
        socket
      ) do
    word_id = Map.get(params, "word_id")
    trimmed_word = word |> to_string() |> String.trim()
    normalized = Vocabulary.normalize_form(trimmed_word)
    {:ok, entry} = Dictionary.lookup(trimmed_word, language: language, target: "en")
    {resolved_word, studied?} = resolve_word(word_id, entry, normalized, language, socket)

    payload =
      entry
      |> Map.take([
        :lemma,
        :part_of_speech,
        :pronunciation,
        :definitions,
        :translation,
        :source_url
      ])
      |> Map.put_new(:definitions, [])
      |> Map.merge(%{
        dom_id: dom_id,
        word: trimmed_word,
        language: language,
        normalized_form: normalized,
        context: nil,
        word_id: resolved_word && resolved_word.id,
        studied: studied?,
        rating_required: false
      })

    {:noreply, push_event(socket, "word-data", payload)}
  end

  @impl true
  def handle_event(
        "add_to_study",
        %{"word_id" => word_id} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, item} <- Study.schedule_new_item(scope.user.id, word.id) do
      studied_word_ids = MapSet.put(socket.assigns.studied_word_ids, word.id)

      studied_forms =
        case normalized_form_from_word(word) do
          nil -> socket.assigns.studied_forms
          form -> MapSet.put(socket.assigns.studied_forms, form)
        end

      # Re-render messages to update word highlighting
      messages =
        if socket.assigns.current_session do
          Session.get_decrypted_messages(socket.assigns.current_session)
        else
          []
        end

      {:noreply,
       socket
       |> assign(:studied_word_ids, studied_word_ids)
       |> assign(:studied_forms, studied_forms)
       |> stream(:messages, messages,
         reset: true,
         dom_id: fn msg ->
           "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
         end
       )
       |> push_event("word-added", %{
         word_id: word.id,
         study_item_id: item.id,
         fsrs_sleep_until: item.due_date,
         dom_id: Map.get(params, "dom_id")
       })
       |> put_flash(:info, "#{word.lemma || word.normalized_form} added to study")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to add word: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("switch_session", %{"session-id" => session_id}, socket) do
    session_id = String.to_integer(session_id)
    user = socket.assigns.current_scope.user

    # Reload sessions list
    sessions = Session.list_user_sessions(user.id, limit: 20)

    # Find the selected session
    current_session = Enum.find(sessions, &(&1.id == session_id))

    socket =
      if current_session do
        messages = Session.get_decrypted_messages(current_session)
        total_tokens = Enum.reduce(messages, 0, fn msg, acc -> acc + (msg.token_count || 0) end)
        {studied_word_ids, studied_forms} = load_studied_words(user.id)

        socket
        |> assign(:current_session, current_session)
        |> assign(:sessions, sessions)
        |> assign(:studied_word_ids, studied_word_ids)
        |> assign(:studied_forms, studied_forms)
        |> assign(:total_tokens, total_tokens)
        |> stream(:messages, messages,
          reset: true,
          dom_id: fn msg ->
            "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
          end
        )
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_session", %{"session-id" => session_id}, socket) do
    session_id = String.to_integer(session_id)
    user = socket.assigns.current_scope.user

    # Find the session to delete
    session_to_delete = Enum.find(socket.assigns.sessions, &(&1.id == session_id))

    socket =
      if session_to_delete do
        # Delete the session
        case Session.delete_session(session_to_delete) do
          {:ok, _} ->
            # Reload sessions list
            sessions = Session.list_user_sessions(user.id, limit: 20)

            # If we deleted the current session, switch to the first available or clear it
            new_current_session =
              if socket.assigns.current_session && socket.assigns.current_session.id == session_id do
                List.first(sessions)
              else
                socket.assigns.current_session
              end

            socket =
              socket
              |> assign(:sessions, sessions)
              |> assign(:current_session, new_current_session)

            # Reload studied words
            {studied_word_ids, studied_forms} = load_studied_words(user.id)

            # If we have a new session, load its messages
            updated_socket =
              if new_current_session do
                messages = Session.get_decrypted_messages(new_current_session)

                total_tokens =
                  Enum.reduce(messages, 0, fn msg, acc -> acc + (msg.token_count || 0) end)

                socket
                |> assign(:studied_word_ids, studied_word_ids)
                |> assign(:studied_forms, studied_forms)
                |> assign(:total_tokens, total_tokens)
                |> stream(:messages, messages,
                  reset: true,
                  dom_id: fn msg ->
                    "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
                  end
                )
              else
                socket
                |> assign(:studied_word_ids, studied_word_ids)
                |> assign(:studied_forms, studied_forms)
                |> assign(:total_tokens, 0)
                |> stream(:messages, [],
                  reset: true,
                  dom_id: fn _msg -> "msg-#{System.unique_integer([:positive])}" end
                )
              end

            updated_socket

          {:error, reason} ->
            Logger.error("Failed to delete session: #{inspect(reason)}")
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_session", _params, socket) do
    user = socket.assigns.current_scope.user

    # Create a new session
    case Session.create_session(user) do
      {:ok, new_session} ->
        # Reload sessions list
        sessions = Session.list_user_sessions(user.id, limit: 20)
        # Reload studied words
        {studied_word_ids, studied_forms} = load_studied_words(user.id)

        socket =
          socket
          |> assign(:current_session, new_session)
          |> assign(:sessions, sessions)
          |> assign(:studied_word_ids, studied_word_ids)
          |> assign(:studied_forms, studied_forms)
          |> assign(:total_tokens, 0)
          |> stream(:messages, [],
            reset: true,
            dom_id: fn _msg -> "msg-#{System.unique_integer([:positive])}" end
          )

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to create new session: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input_value, message)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    if message != "" && !socket.assigns.sending do
      user = socket.assigns.current_scope.user

      # Create session if it doesn't exist
      socket =
        if is_nil(socket.assigns.current_session) do
          case Session.create_session(user) do
            {:ok, session} ->
              # Set title from first message
              Session.update_session_title(session, message)
              # Reload sessions list to include the new session
              sessions = Session.list_user_sessions(user.id, limit: 20)
              # Load any existing messages (should be empty for new session)
              messages = Session.get_decrypted_messages(session)

              socket
              |> assign(:current_session, session)
              |> assign(:sessions, sessions)
              |> stream(:messages, messages,
                reset: true,
                dom_id: fn msg ->
                  "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
                end
              )

            {:error, reason} ->
              Logger.error("Failed to create chat session: #{inspect(reason)}")
              socket
          end
        else
          # Load messages for existing session
          session = socket.assigns.current_session
          messages = Session.get_decrypted_messages(session)

          stream(socket, :messages, messages,
            reset: true,
            dom_id: fn msg ->
              "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
            end
          )
        end

      session = socket.assigns.current_session

      if session do
        # Add user message
        case Session.add_message(session, "user", message) do
          {:ok, user_msg} ->
            socket =
              socket
              |> stream_insert(:messages, user_msg,
                dom_id: "msg-#{DateTime.to_unix(user_msg.inserted_at)}"
              )
              |> assign(:input_value, "")
              |> assign(:sending, true)

            # Send to LLM asynchronously via Task
            parent_pid = self()
            component_id = socket.assigns.myself

            Task.start(fn ->
              send_message_to_llm(session, message, user, parent_pid, component_id)
            end)

            {:noreply, socket}

          {:error, reason} ->
            Logger.error("Failed to add user message: #{inspect(reason)}")
            {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp handle_start_article_chat(socket, assigns) do
    user = socket.assigns.current_scope.user
    article_id = Map.get(assigns, :article_id)
    title = Map.get(assigns, :article_title, "Article")

    attrs = %{
      title: String.slice("#{title} lesson", 0, 60),
      context_type: "article",
      context_id: article_id
    }

    case Session.create_session(user, attrs) do
      {:ok, session} ->
        prompt = build_article_prompt(assigns)

        case Session.add_message(session, "system", prompt) do
          {:ok, _msg} ->
            assign(socket, chat_open: true)
            |> refresh_chat_with_session(session, chat_open: true, sidebar_open: true)

          {:error, reason} ->
            Logger.error("Unable to add article prompt: #{inspect(reason)}")
            assign(socket, chat_open: true)
        end

      {:error, reason} ->
        Logger.error("Failed to create article chat session: #{inspect(reason)}")
        assign(socket, chat_open: true)
    end
  end

  defp build_article_prompt(assigns) do
    language = Map.get(assigns, :article_language, "Spanish")
    topics = Map.get(assigns, :article_topics, []) |> Enum.join(", ")
    excerpt = Map.get(assigns, :article_content, "") |> String.slice(0, 2000)

    """
    You are a conversational tutor leading a friendly lesson based on the supplied article excerpt.
    Focus on summarizing key ideas, asking questions, and revisiting vocabulary or verb tenses drawn from this content.
    Target CEFR level should match the difficulty of the article (#{language}).
    Topics: #{topics}
    Article excerpt:
    #{excerpt}
    """
  end

  defp refresh_chat_with_session(socket, session, opts \\ []) do
    messages = Session.get_decrypted_messages(session)
    total_tokens = Enum.reduce(messages, 0, fn msg, acc -> acc + (msg.token_count || 0) end)
    {studied_word_ids, studied_forms} = load_studied_words(socket.assigns.current_scope.user.id)

    socket
    |> assign(:current_session, session)
    |> assign(:studied_word_ids, studied_word_ids)
    |> assign(:studied_forms, studied_forms)
    |> assign(:total_tokens, total_tokens)
    |> assign(:chat_open, Keyword.get(opts, :chat_open, socket.assigns.chat_open))
    |> assign(:sidebar_open, Keyword.get(opts, :sidebar_open, socket.assigns.sidebar_open))
    |> stream(:messages, messages,
      reset: true,
      dom_id: fn msg ->
        "msg-#{(msg.inserted_at && DateTime.to_unix(msg.inserted_at)) || System.unique_integer([:positive])}"
      end
    )
  end

  # Private helper to send message to LLM in background task
  defp send_message_to_llm(session, user_message, user, parent_pid, _component_id) do
    config = LlmConfig.get_default_config(user.id)

    if config do
      # Decrypt API key for use
      alias Langler.Chat.Encryption

      case Encryption.decrypt_message(user.id, config.encrypted_api_key) do
        {:ok, api_key} ->
          # Trim any whitespace from the API key
          api_key = String.trim(api_key)

          Logger.debug(
            "Decrypted API key length: #{String.length(api_key)}, starts with: #{String.slice(api_key, 0, 10)}"
          )

          # Validate model name through adapter
          temp_config = %{
            api_key: api_key,
            model: config.model || "gpt-4o-mini",
            temperature: config.temperature || 0.7,
            max_tokens: config.max_tokens || 2000
          }

          # This will validate and correct the model name
          case ChatGPT.validate_config(temp_config) do
            {:ok, validated_config} ->
              Logger.debug("Sending to LLM with model: #{validated_config.model}")
              send_to_llm(session, user_message, validated_config, parent_pid)

            {:error, reason} ->
              Logger.error("Invalid LLM config: #{inspect(reason)}")

              send_update(parent_pid, __MODULE__,
                id: "chat-drawer",
                action: :sending_complete
              )
          end

        {:error, reason} ->
          Logger.error("Failed to decrypt API key: #{inspect(reason)}")

          send_update(parent_pid, __MODULE__,
            id: "chat-drawer",
            action: :sending_complete
          )
      end
    else
      Logger.error("No LLM config found for user")

      send_update(parent_pid, __MODULE__,
        id: "chat-drawer",
        action: :sending_complete
      )
    end
  end

  defp send_to_llm(session, user_message, decrypted_config, parent_pid) do
    alias Langler.Chat.RateLimiter

    # Check rate limits before making the request
    user_id = session.user_id

    case RateLimiter.check_rate_limit(user_id, :requests_per_minute) do
      {:ok} ->
        case RateLimiter.check_rate_limit(user_id, :concurrent) do
          {:ok} ->
            # Mark concurrent request start
            RateLimiter.start_concurrent_request(user_id)

            # Get practice words (due or not marked as easy)
            practice_words = Study.get_practice_words(user_id)

            practice_words_text =
              if practice_words != [] do
                words_list = Enum.join(practice_words, ", ")

                "\n\nWords the user is currently learning (use these in conversation when relevant): #{words_list}"
              else
                ""
              end

            # Build messages for LLM
            messages = [
              %{
                role: "system",
                content: """
                You are a helpful language learning assistant.
                The user is learning #{session.target_language} and speaks #{session.native_language}.
                Help them practice by conversing in #{session.target_language}, correcting their mistakes gently, and explaining grammar or vocabulary when needed.#{practice_words_text}
                When returning verb conjugations, format them as a table using the customary format for the language.
                """
              },
              %{role: "user", content: user_message}
            ]

            result = ChatGPT.chat(messages, decrypted_config)

            # Always mark concurrent request end, even on errors
            RateLimiter.end_concurrent_request(user_id)

            # Track the request only on success
            if match?({:ok, _}, result) do
              RateLimiter.track_request(user_id)
            end

            handle_llm_result(result, session, user_message, decrypted_config, parent_pid)

          {:error, :rate_limit_exceeded, retry_after} ->
            Logger.warning(
              "Rate limit: concurrent requests exceeded, retry after #{retry_after}s"
            )

            send_update(parent_pid, __MODULE__,
              id: "chat-drawer",
              action: :sending_complete
            )
        end

      {:error, :rate_limit_exceeded, retry_after} ->
        Logger.warning("Rate limit: requests per minute exceeded, retry after #{retry_after}s")

        send_update(parent_pid, __MODULE__,
          id: "chat-drawer",
          action: :sending_complete
        )
    end
  end

  defp handle_llm_result(result, session, user_message, decrypted_config, parent_pid) do
    case result do
      {:ok, %{content: assistant_content, token_count: tokens}} ->
        # Track token usage
        alias Langler.Chat.RateLimiter
        RateLimiter.track_tokens(session.user_id, tokens)

        # Add assistant message
        case Session.add_message(session, "assistant", assistant_content) do
          {:ok, assistant_msg} ->
            send_update(parent_pid, __MODULE__,
              id: "chat-drawer",
              action: :add_assistant_message,
              message: assistant_msg,
              tokens: tokens
            )

          {:error, reason} ->
            Logger.error("Failed to add assistant message: #{inspect(reason)}")

            send_update(parent_pid, __MODULE__,
              id: "chat-drawer",
              action: :sending_complete
            )
        end

      {:error, {:rate_limit_exceeded, retry_after}} ->
        Logger.warning("OpenAI rate limit exceeded, retrying after #{retry_after}s")
        # Retry with exponential backoff
        retry_with_backoff(session, user_message, decrypted_config, parent_pid, retry_after, 1)

      {:error, :rate_limit_exceeded} ->
        Logger.warning("OpenAI rate limit exceeded (no retry-after header), retrying after 60s")
        retry_with_backoff(session, user_message, decrypted_config, parent_pid, 60, 1)

      {:error, reason} ->
        Logger.error("LLM API call failed: #{inspect(reason)}")

        send_update(parent_pid, __MODULE__,
          id: "chat-drawer",
          action: :sending_complete
        )
    end
  end

  # Retries LLM request with exponential backoff
  defp retry_with_backoff(
         session,
         user_message,
         decrypted_config,
         parent_pid,
         wait_seconds,
         attempt
       )
       when attempt <= 3 do
    Process.sleep(wait_seconds * 1000)

    Logger.info("Retrying LLM request (attempt #{attempt}/3)")

    alias Langler.Chat.RateLimiter

    # Check concurrent limit before retry
    case RateLimiter.check_rate_limit(session.user_id, :concurrent) do
      {:ok} ->
        RateLimiter.start_concurrent_request(session.user_id)

        messages = [
          %{
            role: "system",
            content:
              "You are a helpful language learning assistant. The user is learning #{session.target_language} and speaks #{session.native_language}. Help them practice by conversing in #{session.target_language}, correcting their mistakes gently, and explaining grammar or vocabulary when needed."
          },
          %{role: "user", content: user_message}
        ]

        result = ChatGPT.chat(messages, decrypted_config)

        # Always clean up concurrent request
        RateLimiter.end_concurrent_request(session.user_id)

        case result do
          {:ok, %{content: assistant_content, token_count: tokens}} ->
            RateLimiter.track_tokens(session.user_id, tokens)
            RateLimiter.track_request(session.user_id)

            case Session.add_message(session, "assistant", assistant_content) do
              {:ok, assistant_msg} ->
                send_update(parent_pid, __MODULE__,
                  id: "chat-drawer",
                  action: :add_assistant_message,
                  message: assistant_msg,
                  tokens: tokens
                )

              {:error, reason} ->
                Logger.error("Failed to add assistant message: #{inspect(reason)}")

                send_update(parent_pid, __MODULE__,
                  id: "chat-drawer",
                  action: :sending_complete
                )
            end

          {:error, {:rate_limit_exceeded, retry_after}} ->
            # Exponential backoff: double the wait time
            # Cap at 5 minutes
            next_wait = min(retry_after * 2, 300)

            retry_with_backoff(
              session,
              user_message,
              decrypted_config,
              parent_pid,
              next_wait,
              attempt + 1
            )

          {:error, :rate_limit_exceeded} ->
            next_wait = min((60 * :math.pow(2, attempt)) |> trunc(), 300)

            retry_with_backoff(
              session,
              user_message,
              decrypted_config,
              parent_pid,
              next_wait,
              attempt + 1
            )

          {:error, reason} ->
            Logger.error("LLM API call failed after retry: #{inspect(reason)}")

            send_update(parent_pid, __MODULE__,
              id: "chat-drawer",
              action: :sending_complete
            )
        end

      {:error, :rate_limit_exceeded, _retry_after} ->
        # Concurrent limit hit during retry, give up
        Logger.warning("Concurrent limit hit during retry, aborting")

        send_update(parent_pid, __MODULE__,
          id: "chat-drawer",
          action: :sending_complete
        )
    end
  end

  defp retry_with_backoff(
         _session,
         _user_message,
         _decrypted_config,
         parent_pid,
         _wait_seconds,
         _attempt
       ) do
    Logger.error("LLM request failed after 3 retry attempts")

    send_update(parent_pid, __MODULE__,
      id: "chat-drawer",
      action: :sending_complete
    )
  end

  defp format_date(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  defp format_date(_), do: "Unknown"

  defp filtered_sessions(sessions, search) when is_binary(search) do
    search = String.trim(String.downcase(search))

    if search == "" do
      sessions
    else
      Enum.filter(sessions, fn session ->
        title = (session.title || "Untitled Chat") |> String.downcase()
        String.contains?(title, search)
      end)
    end
  end

  defp filtered_sessions(sessions, _), do: sessions

  defp get_special_chars("spanish"),
    do: ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡", "Á", "É", "Í", "Ó", "Ú", "Ñ", "Ü"]

  defp get_special_chars("french"),
    do: [
      "à",
      "â",
      "ä",
      "é",
      "è",
      "ê",
      "ë",
      "î",
      "ï",
      "ô",
      "ö",
      "ù",
      "û",
      "ü",
      "ÿ",
      "ç",
      "À",
      "Â",
      "Ä",
      "É",
      "È",
      "Ê",
      "Ë",
      "Î",
      "Ï",
      "Ô",
      "Ö",
      "Ù",
      "Û",
      "Ü",
      "Ÿ",
      "Ç"
    ]

  defp get_special_chars("german"), do: ["ä", "ö", "ü", "ß", "Ä", "Ö", "Ü"]

  defp get_special_chars("portuguese"),
    do: [
      "á",
      "à",
      "â",
      "ã",
      "é",
      "ê",
      "í",
      "ó",
      "ô",
      "õ",
      "ú",
      "ü",
      "ç",
      "Á",
      "À",
      "Â",
      "Ã",
      "É",
      "Ê",
      "Í",
      "Ó",
      "Ô",
      "Õ",
      "Ú",
      "Ü",
      "Ç"
    ]

  defp get_special_chars("italian"),
    do: [
      "à",
      "è",
      "é",
      "ì",
      "í",
      "î",
      "ò",
      "ó",
      "ù",
      "ú",
      "À",
      "È",
      "É",
      "Ì",
      "Í",
      "Î",
      "Ò",
      "Ó",
      "Ù",
      "Ú"
    ]

  defp get_special_chars(_), do: []

  defp render_markdown(content) when is_binary(content) do
    case MDEx.to_html(content, extension: [table: true]) do
      {:ok, html} ->
        html

      {:ok, html, _} ->
        html

      {:error, _} ->
        Phoenix.HTML.Engine.html_escape(content)

      other ->
        Logger.warning("Unexpected MDEx return: #{inspect(other)}")
        Phoenix.HTML.Engine.html_escape(content)
    end
  end

  defp render_markdown(_), do: ""

  defp add_word_tooltips(
         html,
         language,
         studied_word_ids,
         studied_forms,
         message_id,
         component_id
       )
       when is_binary(html) do
    case Floki.parse_fragment(html) do
      {:ok, doc} ->
        doc
        |> Floki.traverse_and_update(fn
          {tag, attrs, children} when is_list(children) ->
            # Process text nodes in children
            new_children =
              Enum.flat_map(children, fn
                text when is_binary(text) ->
                  tokenize_and_wrap(
                    text,
                    language,
                    studied_word_ids,
                    studied_forms,
                    message_id,
                    component_id
                  )

                other ->
                  [other]
              end)

            {tag, attrs, new_children}

          other ->
            other
        end)
        |> Floki.raw_html()

      _ ->
        html
    end
  end

  defp add_word_tooltips(html, _, _, _, _, _), do: html

  defp tokenize_and_wrap(
         text,
         language,
         _studied_word_ids,
         studied_forms,
         message_id,
         component_id
       ) do
    @token_regex
    |> Regex.scan(text)
    |> Enum.map(&hd/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn token ->
      trimmed = String.trim(token)
      is_lexical = is_lexical_token?(trimmed)

      if is_lexical do
        normalized = Vocabulary.normalize_form(trimmed)
        studied? = normalized && MapSet.member?(studied_forms, normalized)
        token_id = "chat-word-#{message_id}-#{System.unique_integer([:positive])}"

        component_attr =
          if component_id do
            {"data-component-id", Integer.to_string(component_id)}
          else
            nil
          end

        attrs =
          [
            {"data-word", trimmed},
            {"data-language", language},
            component_attr,
            {"phx-hook", "WordTooltip"},
            {"id", token_id},
            {"class",
             "cursor-pointer rounded transition hover:bg-primary/10 hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary/40" <>
               if(studied?, do: " bg-primary/5 text-primary", else: "")}
          ]
          |> Enum.reject(&is_nil/1)

        {"span", attrs, [token]}
      else
        token
      end
    end)
  end

  defp is_lexical_token?(text) when is_binary(text) do
    String.length(text) > 0 && String.match?(text, ~r/\p{L}/u)
  end

  defp is_lexical_token?(_), do: false

  defp load_studied_words(user_id) do
    items = Study.list_items_for_user(user_id)

    ids = MapSet.new(Enum.map(items, & &1.word_id))

    forms =
      items
      |> Enum.map(&(&1.word && &1.word.normalized_form))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    {ids, forms}
  end

  defp fetch_word(nil), do: {:error, :missing_word_id}

  defp fetch_word(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> fetch_word(parsed)
      _ -> {:error, :invalid_word_id}
    end
  end

  defp fetch_word(id) when is_integer(id) do
    case Vocabulary.get_word(id) do
      nil -> {:error, :word_not_found}
      word -> {:ok, word}
    end
  end

  defp resolve_word(word_id, entry, normalized, language, socket) do
    case resolve_word_record(word_id, entry, normalized, language) do
      {:ok, word} ->
        studied? =
          MapSet.member?(socket.assigns.studied_word_ids, word.id) ||
            MapSet.member?(socket.assigns.studied_forms, normalized_form_from_word(word))

        {word, studied?}

      {:error, _reason} ->
        {nil, MapSet.member?(socket.assigns.studied_forms, normalized)}
    end
  end

  defp resolve_word_record(nil, entry, normalized, language) do
    lemma =
      Map.get(entry, :lemma) || Map.get(entry, "lemma") || Map.get(entry, :word) || entry[:word]

    definitions = Map.get(entry, :definitions) || Map.get(entry, "definitions") || []

    Vocabulary.get_or_create_word(%{
      normalized_form: normalized,
      language: language,
      lemma: lemma,
      part_of_speech: Map.get(entry, :part_of_speech) || Map.get(entry, "part_of_speech"),
      definitions: definitions
    })
  end

  defp resolve_word_record(word_id, _entry, _normalized, _language) do
    fetch_word(word_id)
  end

  defp normalized_form_from_word(word) when is_nil(word), do: nil

  defp normalized_form_from_word(word) do
    word.normalized_form
  end
end

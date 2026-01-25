defmodule LanglerWeb.ChatLive.Drawer do
  @moduledoc """
  LiveComponent for the chat drawer interface.
  Renders in the bottom-right corner of the screen as a slide-out drawer.
  """
  use LanglerWeb, :live_component

  alias Ecto.NoResultsError
  alias Langler.Accounts.GoogleTranslateConfig
  alias Langler.Accounts.LlmConfig
  alias Langler.Chat.Session
  alias Langler.Content
  alias Langler.External.Dictionary
  alias Langler.LLM.Adapters.ChatGPT
  alias Langler.Quizzes
  alias Langler.Quizzes.Result
  alias Langler.Quizzes.Service
  alias Langler.Quizzes.State
  alias Langler.Study
  alias Langler.Vocabulary

  import LanglerWeb.ChatLive.ChatHeader
  import LanglerWeb.ChatLive.ChatInput
  import LanglerWeb.ChatLive.EmptyState
  import LanglerWeb.ChatLive.SessionItem
  import LanglerWeb.ChatLive.SpecialCharactersKeyboard

  alias Phoenix.HTML.Engine, as: HtmlEngine

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
      |> assign_defaults(assigns)
      |> maybe_stream_messages()
      |> handle_update_action(assigns)

    {:ok, socket}
  end

  defp assign_defaults(socket, assigns) do
    socket
    |> assign(assigns)
    |> assign_new(:chat_open, fn -> false end)
    |> assign_new(:sidebar_open, fn -> false end)
    |> assign_new(:keyboard_open, fn -> false end)
    |> assign_new(:fullscreen, fn -> false end)
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
    |> assign_new(:renaming_session_id, fn -> nil end)
    |> assign_new(:rename_input_value, fn -> nil end)
    |> assign_new(:open_menu_id, fn -> nil end)
    |> State.init()
  end

  defp handle_update_action(socket, assigns) do
    case Map.get(assigns, :action) do
      :add_assistant_message ->
        handle_add_assistant_message(socket, assigns)

      :start_article_chat ->
        handle_start_article_chat(socket, assigns)

      :start_article_quiz ->
        handle_start_article_quiz(socket, assigns)

      :sending_complete ->
        assign(socket, :sending, false)

      _ ->
        socket
    end
  end

  defp handle_add_assistant_message(socket, assigns) do
    dom_id = message_dom_id(assigns.message)

    socket =
      socket
      |> stream_insert(:messages, assigns.message, dom_id: dom_id)
      |> assign(:sending, false)
      |> assign(:total_tokens, socket.assigns.total_tokens + assigns.tokens)
      |> push_event("chat:scroll-bottom", %{})

    apply_quiz_result_action(socket, assigns)
  end

  defp apply_quiz_result_action(socket, %{quiz_result_action: :quiz_completed} = assigns) do
    case normalize_quiz_result(Map.get(assigns, :quiz_result_map)) do
      {:ok, result} ->
        socket
        |> assign(:quiz_completed, true)
        |> assign(:quiz_result, result)

      :error ->
        put_flash(socket, :error, "Quiz completed but result could not be displayed.")
    end
  end

  defp apply_quiz_result_action(socket, %{quiz_result_action: {:quiz_error, reason}})
       when is_binary(reason) do
    put_flash(socket, :error, "Failed to save quiz result: #{reason}")
  end

  defp apply_quiz_result_action(socket, %{quiz_result_action: {:quiz_error, _reason}}) do
    put_flash(socket, :error, "Failed to save quiz result. Please try again.")
  end

  defp apply_quiz_result_action(socket, %{quiz_result_action: :quiz_parse_error}) do
    put_flash(
      socket,
      :error,
      "Quiz result couldn't be processed. The quiz may still be in progress or the format was invalid."
    )
  end

  defp apply_quiz_result_action(socket, _assigns), do: socket

  defp normalize_quiz_result(%Result{} = result), do: {:ok, result}

  defp normalize_quiz_result(%{} = result_map) do
    case Result.from_map(result_map) do
      {:ok, quiz_result} -> {:ok, quiz_result}
      {:error, _reason} -> :error
    end
  end

  defp normalize_quiz_result(_), do: :error

  defp maybe_stream_messages(socket) do
    messages = socket.assigns.messages || []

    dom_id_fn = fn msg ->
      case msg.inserted_at do
        %DateTime{} = dt -> "msg-#{DateTime.to_unix(dt)}"
        _ -> "msg-#{System.unique_integer([:positive])}"
      end
    end

    case messages do
      list when is_list(list) and list != [] ->
        stream(socket, :messages, list, dom_id: dom_id_fn)

      _ ->
        stream(socket, :messages, [], dom_id: dom_id_fn)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="chat-drawer-container"
      phx-component="chat-drawer"
      phx-hook="ChatDrawerState"
      class={[
        "fixed bottom-0 right-0 z-[60]",
        @chat_open && "chat-open",
        @fullscreen && "chat-fullscreen"
      ]}
    >
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
          "chat-drawer-panel fixed inset-y-0 right-0 flex bg-base-100/70 backdrop-blur-md transition-transform duration-300 ease-in-out",
          "lg:bg-transparent lg:backdrop-blur-0",
          @chat_open && "translate-x-0 opacity-100",
          !@chat_open && "translate-x-full opacity-0 pointer-events-none",
          @fullscreen && "chat-drawer-fullscreen"
        ]}
        aria-hidden={!@chat_open}
      >
        <%!-- Sidebar --%>
        <div
          id="chat-drawer-sidebar"
          class={[
            "flex flex-col border-r border-base-200 bg-base-200/70 transition-all duration-300 relative",
            if(@sidebar_open, do: "w-64", else: "w-0 overflow-hidden")
          ]}
        >
          <div class="flex h-full flex-col overflow-hidden">
            <%!-- New Chat Button --%>
            <div :if={@sidebar_open} class="p-2">
              <button
                type="button"
                phx-click="new_session"
                phx-target={@myself}
                class="w-full btn btn-primary btn-sm gap-2"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> New Chat
              </button>
            </div>

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
            <div :if={@sidebar_open} class="flex-1 px-2 flex flex-col">
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/60 px-2 py-1 mb-1">
                Your Chats
              </div>
              <div class="flex-1 space-y-1 overflow-y-auto pr-1">
                <.session_item
                  :for={session <- filtered_sessions(@sessions, @session_search)}
                  session={session}
                  is_current={@current_session && session.id == @current_session.id}
                  is_renaming={@renaming_session_id == session.id}
                  rename_value={@rename_input_value}
                  menu_open={@open_menu_id == session.id}
                  myself={@myself}
                />
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
        <div class={[
          "chat-drawer-main min-w-0",
          @fullscreen && "chat-drawer-fullscreen"
        ]}>
          <%!-- Header --%>
          <.chat_header current_session={@current_session} myself={@myself} fullscreen={@fullscreen} />

          <%!-- Messages Area --%>
          <div id="chat-main-area" class="chat-main-area" phx-hook="ChatAutoScroll">
            <%= if @current_session == nil do %>
              <.empty_state llm_config_missing={@llm_config_missing} />
            <% else %>
              <div class="space-y-4" id="chat-messages" phx-update="stream">
                <div
                  :for={{id, msg} <- @streams.messages}
                  :if={msg.role in ["user", "assistant"]}
                  id={id}
                  class={[
                    "chat-message-enter flex gap-3",
                    msg.role == "user" && "justify-end",
                    msg.role != "user" && "justify-start"
                  ]}
                >
                  <%= if msg.role == "user" do %>
                    <div class="flex flex-col items-end gap-2 max-w-[80%] sm:max-w-[70%]">
                      <div class="chat-bubble chat-bubble-primary bg-gradient-to-br from-primary to-primary/80 text-primary-content rounded-2xl rounded-tr-sm px-4 py-3 shadow-lg">
                        <p class="text-sm leading-relaxed whitespace-pre-wrap break-words">
                          {msg.content}
                        </p>
                      </div>
                    </div>
                  <% else %>
                    <div class="flex items-start gap-3 max-w-[80%] sm:max-w-[70%]">
                      <div class="avatar placeholder">
                        <div class="bg-primary/20 text-primary rounded-full w-8 h-8 flex items-center justify-center">
                          <.icon name="hero-sparkles" class="h-4 w-4" />
                        </div>
                      </div>
                      <div class="flex flex-col gap-2 flex-1">
                        <div class="chat-bubble bg-base-200 text-base-content rounded-2xl rounded-tl-sm px-4 py-3 shadow-md">
                          <%= if @current_session do %>
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
                            <p class="text-sm leading-relaxed whitespace-pre-wrap break-words">
                              {msg.content}
                            </p>
                          <% end %>
                        </div>
                        <div class="flex items-center gap-2 text-xs text-base-content/50">
                          <button
                            type="button"
                            class="btn btn-ghost btn-xs gap-1 px-2 py-1 transition hover:bg-base-200/60 rounded-full"
                            phx-hook="CopyToClipboard"
                            id={"copy-message-#{id}"}
                            data-copy-text={msg.content}
                            aria-label="Copy message"
                          >
                            <.icon name="hero-clipboard-document" class="h-3 w-3" /> Copy
                          </button>
                          <button
                            type="button"
                            class="btn btn-ghost btn-xs gap-1 px-2 py-1 transition hover:bg-base-200/60 rounded-full"
                            phx-hook="TextDownloader"
                            id={"download-message-#{id}"}
                            data-download-text={msg.content}
                            data-download-filename={"langler-response-" <> id <> ".txt"}
                            aria-label="Download message"
                          >
                            <.icon name="hero-arrow-down-tray" class="h-3 w-3" /> Download
                          </button>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
              <div
                :if={@sending}
                class="flex items-start gap-3 mt-4"
                aria-live="polite"
                aria-label="Assistant is typing"
              >
                <div class="avatar placeholder">
                  <div class="bg-primary/20 text-primary rounded-full w-8 h-8 flex items-center justify-center">
                    <.icon name="hero-sparkles" class="h-4 w-4" />
                  </div>
                </div>
                <div class="chat-bubble bg-base-200 text-base-content/70 flex items-center gap-2 rounded-2xl rounded-tl-sm px-4 py-3 shadow-md">
                  <span class="loading loading-dots loading-sm text-primary"></span>
                  <span class="text-xs uppercase tracking-wide text-base-content/50">
                    Thinking...
                  </span>
                </div>
              </div>

              <%!-- Quiz Result Display --%>
              <.quiz_results
                :if={@quiz_completed && @quiz_result}
                result={@quiz_result}
                myself={@myself}
              />
            <% end %>
          </div>

          <%!-- Input Area --%>
          <div class="border-t border-base-200 bg-base-200/50">
            <.special_characters_keyboard
              :if={@current_session}
              target_language={@current_session.target_language}
              myself={@myself}
              is_open={@keyboard_open}
            />
            <.chat_input
              input_value={@input_value}
              sending={@sending}
              llm_config_missing={@llm_config_missing}
              total_tokens={@total_tokens}
              show_tokens={@current_session != nil}
              myself={@myself}
            />
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
        open_chat_drawer(socket)
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
  def handle_event("toggle_fullscreen", _params, socket) do
    {:noreply, assign(socket, :fullscreen, !socket.assigns.fullscreen)}
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

    user_id = socket.assigns.current_scope.user.id
    api_key = GoogleTranslateConfig.get_api_key(user_id)

    case Dictionary.lookup(trimmed_word,
           language: language,
           target: "en",
           api_key: api_key,
           user_id: user_id
         ) do
      {:ok, entry} ->
        {resolved_word, studied?} = resolve_word(word_id, entry, normalized, language, socket)

        handle_successful_lookup_chat(socket, %{
          entry: entry,
          resolved_word: resolved_word,
          studied?: studied?,
          trimmed_word: trimmed_word,
          normalized: normalized,
          language: language,
          dom_id: dom_id
        })

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Please configure Google Translate or an LLM in settings to use dictionary lookups."
         )}
    end
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
  def handle_event(
        "remove_from_study",
        %{"word_id" => word_id} = params,
        %{assigns: %{current_scope: scope}} = socket
      ) do
    with {:ok, word} <- fetch_word(word_id),
         {:ok, _} <- Study.remove_item(scope.user.id, word.id) do
      studied_word_ids = MapSet.delete(socket.assigns.studied_word_ids, word.id)

      studied_forms =
        case normalized_form_from_word(word) do
          nil -> socket.assigns.studied_forms
          form -> MapSet.delete(socket.assigns.studied_forms, form)
        end

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
       |> push_event("word-removed", %{word_id: word.id, dom_id: Map.get(params, "dom_id")})}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to remove word: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("switch_session", %{"session-id" => session_id}, socket) do
    session_id = String.to_integer(session_id)
    user = socket.assigns.current_scope.user

    # Reload sessions list
    sessions = Session.list_user_sessions(user.id, limit: 20)

    # Find the selected session
    current_session = find_session_by_id(sessions, session_id)

    socket =
      if current_session do
        messages = Session.get_decrypted_messages(current_session)
        total_tokens = total_tokens(messages)
        {studied_word_ids, studied_forms} = load_studied_words(user.id)

        socket
        |> assign(:current_session, current_session)
        |> assign(:sessions, sessions)
        |> assign(:studied_word_ids, studied_word_ids)
        |> assign(:studied_forms, studied_forms)
        |> assign(:total_tokens, total_tokens)
        |> reset_messages_stream(messages)
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
    session_to_delete = find_session_by_id(socket.assigns.sessions, session_id)

    socket =
      case session_to_delete do
        nil ->
          socket

        _ ->
          case Session.delete_session(session_to_delete) do
            {:ok, _} ->
              refresh_after_session_delete(socket, user, session_id)

            {:error, reason} ->
              Logger.error("Failed to delete session: #{inspect(reason)}")
              socket
          end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("rename_session", %{"session-id" => session_id}, socket) do
    session_id = String.to_integer(session_id)
    session = find_session_by_id(socket.assigns.sessions, session_id)

    socket =
      if session do
        socket
        |> assign(:renaming_session_id, session_id)
        |> assign(:rename_input_value, session.title || "")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_rename", %{"session-id" => session_id, "title" => title}, socket) do
    session_id = String.to_integer(session_id)
    user = socket.assigns.current_scope.user
    session = find_session_by_id(socket.assigns.sessions, session_id)

    socket =
      if session do
        case Session.update_session_title(session, title, 60) do
          {:ok, _updated_session} ->
            sessions = Session.list_user_sessions(user.id, limit: 20)

            socket
            |> assign(:sessions, sessions)
            |> assign(:renaming_session_id, nil)
            |> assign(:rename_input_value, nil)
            |> assign(:open_menu_id, nil)

          {:error, reason} ->
            Logger.error("Failed to rename session: #{inspect(reason)}")

            socket
            |> put_flash(:error, "Failed to rename chat")
            |> assign(:open_menu_id, nil)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    {:noreply,
     socket
     |> assign(:renaming_session_id, nil)
     |> assign(:rename_input_value, nil)}
  end

  @impl true
  def handle_event("toggle_chat_menu", params, socket) do
    session_id = params |> Map.get("session-id") |> String.to_integer()
    current_menu_id = socket.assigns.open_menu_id

    open_menu_id =
      if current_menu_id == session_id do
        nil
      else
        session_id
      end

    {:noreply, assign(socket, :open_menu_id, open_menu_id)}
  end

  @impl true
  def handle_event("close_chat_menu", _params, socket) do
    {:noreply, assign(socket, :open_menu_id, nil)}
  end

  @impl true
  def handle_event("toggle_pin_session", %{"session-id" => session_id}, socket) do
    session_id = String.to_integer(session_id)
    user = socket.assigns.current_scope.user
    session = find_session_by_id(socket.assigns.sessions, session_id)

    socket =
      if session do
        case Session.toggle_pin(session) do
          {:ok, _updated_session} ->
            sessions = Session.list_user_sessions(user.id, limit: 20)

            socket
            |> assign(:sessions, sessions)
            |> assign(:open_menu_id, nil)

          {:error, reason} ->
            Logger.error("Failed to toggle pin: #{inspect(reason)}")

            socket
            |> put_flash(:error, "Failed to pin/unpin chat")
            |> assign(:open_menu_id, nil)
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
  def handle_event("finish_and_archive", _params, socket) do
    case socket.assigns.current_session do
      %{context_type: context_type, context_id: article_id}
      when context_type == "article_quiz" ->
        user_id = socket.assigns.current_scope.user.id

        case Content.finish_article_for_user(user_id, article_id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Article marked as finished and archived")
             |> push_navigate(to: ~p"/articles")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Unable to finish article: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Not a quiz session")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    cond do
      message == "" ->
        {:noreply, socket}

      socket.assigns.sending ->
        {:noreply, socket}

      true ->
        user = socket.assigns.current_scope.user

        case ensure_session_ready(socket, user, message) do
          {:ok, socket, session} ->
            add_user_message_and_dispatch(socket, session, message, user)

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  defp handle_successful_lookup_chat(socket, %{
         entry: entry,
         resolved_word: resolved_word,
         studied?: studied?,
         trimmed_word: trimmed_word,
         normalized: normalized,
         language: language,
         dom_id: dom_id
       }) do
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

  defp ensure_session_ready(socket, user, message) do
    case socket.assigns.current_session do
      nil ->
        create_session_and_load(socket, user, message)

      session ->
        {:ok, reset_messages_stream(socket, Session.get_decrypted_messages(session)), session}
    end
  end

  defp create_session_and_load(socket, user, message) do
    case Session.create_session(user) do
      {:ok, session} ->
        Session.update_session_title(session, message)
        sessions = Session.list_user_sessions(user.id, limit: 20)
        messages = Session.get_decrypted_messages(session)

        socket =
          socket
          |> assign(:current_session, session)
          |> assign(:sessions, sessions)
          |> reset_messages_stream(messages)

        {:ok, socket, session}

      {:error, reason} ->
        Logger.error("Failed to create chat session: #{inspect(reason)}")
        {:error, socket}
    end
  end

  defp reset_messages_stream(socket, messages) do
    stream(socket, :messages, messages, reset: true, dom_id: &message_dom_id/1)
  end

  defp message_dom_id(msg) do
    timestamp =
      if msg.inserted_at do
        DateTime.to_unix(msg.inserted_at)
      else
        System.unique_integer([:positive])
      end

    "msg-#{timestamp}"
  end

  # Helper functions for handle_event("toggle_chat", ...)
  defp open_chat_drawer(socket) do
    user = socket.assigns.current_scope.user
    default_config = LlmConfig.get_default_config(user.id)
    sessions = Session.list_user_sessions(user.id, limit: 20)
    current_session = List.first(sessions)
    {studied_word_ids, studied_forms} = load_studied_words(user.id)

    socket
    |> assign(:chat_open, true)
    |> assign(:sessions, sessions)
    |> assign(:sidebar_open, false)
    |> assign(:session_search, "")
    |> assign(:studied_word_ids, studied_word_ids)
    |> assign(:studied_forms, studied_forms)
    |> assign(:llm_config_missing, is_nil(default_config))
    |> load_session_messages(current_session)
  end

  defp load_session_messages(socket, nil) do
    socket
    |> assign(:current_session, nil)
    |> assign(:total_tokens, 0)
    |> stream(:messages, [],
      reset: true,
      dom_id: fn _msg -> "msg-#{System.unique_integer([:positive])}" end
    )
  end

  defp load_session_messages(socket, current_session) do
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
  end

  defp add_user_message_and_dispatch(socket, session, message, user) do
    case Session.add_message(session, "user", message) do
      {:ok, user_msg} ->
        socket =
          socket
          |> stream_insert(:messages, user_msg,
            dom_id: "msg-#{DateTime.to_unix(user_msg.inserted_at)}"
          )
          |> assign(:input_value, "")
          |> assign(:sending, true)
          |> push_event("chat:scroll-bottom", %{instant: true})

        dispatch_llm_request(session, message, user, socket.assigns.myself)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Failed to add user message: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  defp refresh_after_session_delete(socket, user, session_id) do
    sessions = Session.list_user_sessions(user.id, limit: 20)

    new_current_session =
      pick_current_session_after_delete(socket.assigns.current_session, sessions, session_id)

    socket =
      socket
      |> assign(:sessions, sessions)
      |> assign(:current_session, new_current_session)

    {studied_word_ids, studied_forms} = load_studied_words(user.id)

    socket
    |> assign(:studied_word_ids, studied_word_ids)
    |> assign(:studied_forms, studied_forms)
    |> load_session_messages(new_current_session)
  end

  defp pick_current_session_after_delete(nil, _sessions, _session_id), do: nil

  defp pick_current_session_after_delete(current_session, sessions, session_id) do
    if current_session.id == session_id do
      List.first(sessions)
    else
      current_session
    end
  end

  defp total_tokens(messages) do
    Enum.reduce(messages, 0, fn msg, acc -> acc + (msg.token_count || 0) end)
  end

  defp find_session_by_id(sessions, session_id) do
    Enum.find(sessions, &(&1.id == session_id))
  end

  defp dispatch_llm_request(session, message, user, component_id) do
    parent_pid = self()

    Task.start(fn ->
      send_message_to_llm(session, message, user, parent_pid, component_id)
    end)
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

  defp handle_start_article_quiz(socket, assigns) do
    user = socket.assigns.current_scope.user

    case Service.start_quiz_session(assigns, user) do
      {:ok, session} ->
        send_initial_quiz_message(socket, session, user)

      {:error, reason} ->
        Logger.error("Failed to start quiz session: #{inspect(reason)}")
        assign(socket, chat_open: true)
    end
  end

  defp send_initial_quiz_message(socket, session, user) do
    initial_message = Quizzes.initial_quiz_message()

    case Session.add_message(session, "user", initial_message) do
      {:ok, user_msg} ->
        socket =
          socket
          |> initialize_quiz_socket(session)
          |> assign(sending: true)
          |> stream_insert(:messages, user_msg,
            dom_id: "msg-#{DateTime.to_unix(user_msg.inserted_at)}"
          )
          |> push_event("chat:scroll-bottom", %{instant: true})

        # Dispatch LLM request to get first question
        dispatch_llm_request(session, initial_message, user, socket.assigns.myself)

        socket

      {:error, reason} ->
        Logger.error("Unable to add initial quiz message: #{inspect(reason)}")
        initialize_quiz_socket(socket, session)
    end
  end

  defp initialize_quiz_socket(socket, session) do
    socket
    |> assign(chat_open: true)
    |> State.reset()
    |> refresh_chat_with_session(session, chat_open: true, sidebar_open: true)
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

  defp article_context_messages(%{context_type: "article"} = session, history_messages) do
    excerpt_already_present? =
      Enum.any?(history_messages, fn
        %{role: "system", content: content} -> String.contains?(content, "Article excerpt:")
        _ -> false
      end)

    cond do
      excerpt_already_present? ->
        []

      is_nil(session.context_id) ->
        []

      true ->
        case fetch_article(session.context_id) do
          {:ok, article} ->
            topics =
              article.id
              |> Content.list_topics_for_article()
              |> Enum.map(& &1.topic)

            prompt =
              build_article_prompt(%{
                article_language: article.language,
                article_topics: topics,
                article_content: article.content
              })

            [%{role: "system", content: prompt}]

          _ ->
            []
        end
    end
  end

  defp article_context_messages(_, _), do: []

  defp fetch_article(article_id) when is_integer(article_id) do
    {:ok, Content.get_article!(article_id)}
  rescue
    NoResultsError -> :error
  end

  defp fetch_article(_), do: :error

  defp refresh_chat_with_session(socket, session, opts) do
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
      process_llm_config(session, user_message, user, config, parent_pid)
    else
      handle_no_config(parent_pid)
    end
  end

  defp process_llm_config(session, user_message, user, config, parent_pid) do
    alias Langler.Chat.Encryption

    case Encryption.decrypt_message(user.id, config.encrypted_api_key) do
      {:ok, api_key} -> handle_decrypted_key(session, user_message, api_key, config, parent_pid)
      {:error, reason} -> handle_decrypt_error(reason, parent_pid)
    end
  end

  defp handle_decrypted_key(session, user_message, api_key, config, parent_pid) do
    trimmed_key = String.trim(api_key)

    Logger.debug(
      "Decrypted API key length: #{String.length(trimmed_key)}, starts with: #{String.slice(trimmed_key, 0, 10)}"
    )

    temp_config = build_temp_config(trimmed_key, config)

    case ChatGPT.validate_config(temp_config) do
      {:ok, validated_config} ->
        handle_validated_config(session, user_message, validated_config, parent_pid)

      {:error, reason} ->
        handle_validation_error(reason, parent_pid)
    end
  end

  defp build_temp_config(api_key, config) do
    %{
      api_key: api_key,
      model: config.model || "gpt-4o-mini",
      temperature: config.temperature || 0.7,
      max_tokens: config.max_tokens || 2000
    }
  end

  defp handle_validated_config(session, user_message, validated_config, parent_pid) do
    Logger.debug("Sending to LLM with model: #{validated_config.model}")
    send_to_llm(session, user_message, validated_config, parent_pid)
  end

  defp handle_validation_error(reason, parent_pid) do
    Logger.error("Invalid LLM config: #{inspect(reason)}")
    send_complete_update(parent_pid)
  end

  defp handle_decrypt_error(reason, parent_pid) do
    Logger.error("Failed to decrypt API key: #{inspect(reason)}")
    send_complete_update(parent_pid)
  end

  defp handle_no_config(parent_pid) do
    Logger.error("No LLM config found for user")
    send_complete_update(parent_pid)
  end

  defp send_complete_update(parent_pid) do
    send_update(parent_pid, __MODULE__,
      id: "chat-drawer",
      action: :sending_complete
    )
  end

  defp send_to_llm(session, user_message, decrypted_config, parent_pid) do
    alias Langler.Chat.RateLimiter

    user_id = session.user_id

    case RateLimiter.check_rate_limit(user_id, :requests_per_minute) do
      {:ok} ->
        check_concurrent_rate_limit(session, user_message, decrypted_config, parent_pid, user_id)

      {:error, :rate_limit_exceeded, retry_after} ->
        handle_rate_limit_error(parent_pid, retry_after, "requests per minute")
    end
  end

  defp check_concurrent_rate_limit(session, user_message, decrypted_config, parent_pid, user_id) do
    alias Langler.Chat.RateLimiter

    case RateLimiter.check_rate_limit(user_id, :concurrent) do
      {:ok} ->
        process_llm_request(session, user_message, decrypted_config, parent_pid, user_id)

      {:error, :rate_limit_exceeded, retry_after} ->
        handle_rate_limit_error(parent_pid, retry_after, "concurrent requests")
    end
  end

  defp process_llm_request(session, user_message, decrypted_config, parent_pid, user_id) do
    alias Langler.Chat.RateLimiter

    RateLimiter.start_concurrent_request(user_id)

    messages = build_messages(session, user_message, user_id)
    result = ChatGPT.chat(messages, decrypted_config)

    RateLimiter.end_concurrent_request(user_id)

    if match?({:ok, _}, result) do
      RateLimiter.track_request(user_id)
    end

    handle_llm_result(result, session, user_message, decrypted_config, parent_pid)
  end

  defp build_messages(session, user_message, user_id) do
    practice_words_text = build_practice_words_text(user_id)
    base_system_message = build_system_message(session, practice_words_text)

    history_messages = get_history_messages(session)
    history_messages = ensure_user_message_in_history(history_messages, user_message)
    context_messages = article_context_messages(session, history_messages)

    [%{role: "system", content: base_system_message}] ++ context_messages ++ history_messages
  end

  defp build_practice_words_text(user_id) do
    practice_words = Study.get_practice_words(user_id)

    if practice_words != [] do
      words_list = Enum.join(practice_words, ", ")

      "\n\nWords the user is currently learning (use these in conversation when relevant): #{words_list}"
    else
      ""
    end
  end

  defp build_system_message(session, practice_words_text) do
    """
    You are a helpful language learning assistant.
    The user is learning #{session.target_language} and speaks #{session.native_language}.
    Help them practice by conversing in #{session.target_language}, correcting their mistakes gently, and explaining grammar or vocabulary when needed.#{practice_words_text}
    When returning verb conjugations, format them as a table using the customary format for the language.
    """
  end

  defp get_history_messages(session) do
    session
    |> Session.get_decrypted_messages()
    |> Enum.map(fn message -> Map.take(message, [:role, :content]) end)
  end

  defp ensure_user_message_in_history(history_messages, user_message) do
    if Enum.any?(history_messages, fn msg ->
         msg.role == "user" and msg.content == user_message
       end) do
      history_messages
    else
      history_messages ++ [%{role: "user", content: user_message}]
    end
  end

  defp handle_rate_limit_error(parent_pid, retry_after, limit_type) do
    Logger.warning("Rate limit: #{limit_type} exceeded, retry after #{retry_after}s")

    send_update(parent_pid, __MODULE__,
      id: "chat-drawer",
      action: :sending_complete
    )
  end

  @dialyzer {:nowarn_function, handle_llm_result: 5}
  defp handle_llm_result(
         {:ok, %{content: assistant_content, token_count: tokens}},
         session,
         _user_message,
         _decrypted_config,
         parent_pid
       ) do
    # Track token usage
    alias Langler.Chat.RateLimiter
    RateLimiter.track_tokens(session.user_id, tokens)

    case Session.add_message(session, "assistant", assistant_content) do
      {:ok, assistant_msg} ->
        {quiz_result_action, quiz_result} =
          Service.handle_quiz_result(session, assistant_content)

        send_update(parent_pid, __MODULE__,
          id: "chat-drawer",
          action: :add_assistant_message,
          message: assistant_msg,
          tokens: tokens,
          quiz_result_action: quiz_result_action,
          quiz_result_map: quiz_result
        )

      {:error, reason} ->
        Logger.error("Failed to add assistant message: #{inspect(reason)}")
        send_complete_update(parent_pid)
    end
  end

  defp handle_llm_result(
         {:error, {:rate_limit_exceeded, retry_after}},
         session,
         user_message,
         decrypted_config,
         parent_pid
       ) do
    Logger.warning("OpenAI rate limit exceeded, retrying after #{retry_after}s")
    # Retry with exponential backoff
    retry_with_backoff(session, user_message, decrypted_config, parent_pid, retry_after, 1)
  end

  defp handle_llm_result({:error, reason}, _session, _user_message, _decrypted_config, parent_pid) do
    Logger.error("LLM API call failed: #{inspect(reason)}")
    send_complete_update(parent_pid)
  end

  # Retries LLM request with exponential backoff
  @dialyzer {:nowarn_function, retry_with_backoff: 6}
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
        process_retry_request(session, user_message, decrypted_config, parent_pid, attempt)

      {:error, :rate_limit_exceeded, _retry_after} ->
        handle_concurrent_limit_during_retry(parent_pid)
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

  defp process_retry_request(session, user_message, decrypted_config, parent_pid, attempt) do
    alias Langler.Chat.RateLimiter

    RateLimiter.start_concurrent_request(session.user_id)

    messages = build_retry_messages(session, user_message)
    result = ChatGPT.chat(messages, decrypted_config)

    RateLimiter.end_concurrent_request(session.user_id)

    handle_retry_result(result, session, user_message, decrypted_config, parent_pid, attempt)
  end

  defp build_retry_messages(session, user_message) do
    [
      %{
        role: "system",
        content:
          "You are a helpful language learning assistant. The user is learning #{session.target_language} and speaks #{session.native_language}. Help them practice by conversing in #{session.target_language}, correcting their mistakes gently, and explaining grammar or vocabulary when needed."
      },
      %{role: "user", content: user_message}
    ]
  end

  defp handle_retry_result(result, session, user_message, decrypted_config, parent_pid, attempt) do
    case result do
      {:ok, %{content: assistant_content, token_count: tokens}} ->
        handle_successful_retry(session, assistant_content, tokens, parent_pid)

      {:error, {:rate_limit_exceeded, retry_after}} ->
        next_wait = min(retry_after * 2, 300)

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
        send_complete_update(parent_pid)
    end
  end

  defp handle_successful_retry(session, assistant_content, tokens, parent_pid) do
    alias Langler.Chat.RateLimiter

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
        send_complete_update(parent_pid)
    end
  end

  defp handle_concurrent_limit_during_retry(parent_pid) do
    Logger.warning("Concurrent limit hit during retry, aborting")
    send_complete_update(parent_pid)
  end

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

  @dialyzer {:nowarn_function, render_markdown: 1}
  defp render_markdown(content) when is_binary(content) do
    case MDEx.to_html(content, extension: [table: true]) do
      {:ok, html} ->
        html

      {:ok, html, _} ->
        html

      {:error, _} ->
        HtmlEngine.html_escape(content)

      other ->
        Logger.warning("Unexpected MDEx return: #{inspect(other)}")
        HtmlEngine.html_escape(content)
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
        process_html_document(
          doc,
          language,
          studied_word_ids,
          studied_forms,
          message_id,
          component_id
        )

      _ ->
        html
    end
  end

  defp add_word_tooltips(html, _, _, _, _, _), do: html

  defp process_html_document(
         doc,
         language,
         studied_word_ids,
         studied_forms,
         message_id,
         component_id
       ) do
    doc
    |> Floki.traverse_and_update(fn
      {tag, attrs, children} when is_list(children) ->
        new_children =
          process_html_children(
            children,
            language,
            studied_word_ids,
            studied_forms,
            message_id,
            component_id
          )

        {tag, attrs, new_children}

      other ->
        other
    end)
    |> Floki.raw_html()
  end

  defp process_html_children(
         children,
         language,
         studied_word_ids,
         studied_forms,
         message_id,
         component_id
       ) do
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
  end

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
      wrap_token_if_lexical(token, language, studied_forms, message_id, component_id)
    end)
  end

  defp wrap_token_if_lexical(token, language, studied_forms, message_id, component_id) do
    trimmed = String.trim(token)

    if lexical_token?(trimmed) do
      build_wrapped_token(trimmed, language, studied_forms, message_id, component_id, token)
    else
      token
    end
  end

  defp build_wrapped_token(trimmed, language, studied_forms, message_id, component_id, token) do
    normalized = Vocabulary.normalize_form(trimmed)
    studied? = normalized && MapSet.member?(studied_forms, normalized)
    token_id = "chat-word-#{message_id}-#{System.unique_integer([:positive])}"
    component_attr = build_component_attr(component_id)
    attrs = build_token_attrs(trimmed, language, component_attr, token_id, studied?)

    {"span", attrs, [token]}
  end

  defp build_component_attr(nil), do: nil
  defp build_component_attr(component_id), do: {"data-component-id", to_string(component_id)}

  defp build_token_attrs(trimmed, language, component_attr, token_id, studied?) do
    class_base =
      "cursor-pointer rounded transition hover:bg-primary/10 hover:text-primary focus-visible:outline focus-visible:outline-2 focus-visible:outline-primary/40"

    class_suffix = if studied?, do: " bg-primary/5 text-primary", else: ""

    [
      {"data-word", trimmed},
      {"data-language", language},
      component_attr,
      {"phx-hook", "WordTooltip"},
      {"id", token_id},
      {"class", class_base <> class_suffix}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp lexical_token?(text) when is_binary(text) do
    String.length(text) > 0 && String.match?(text, ~r/\p{L}/u)
  end

  @dialyzer {:nowarn_function, lexical_token?: 1}
  defp lexical_token?(_), do: false

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

defmodule LanglerWeb.ChatLive.ChatHeader do
  @moduledoc """
  Functional component for the chat drawer header.

  Displays the chat title and action buttons (keyboard toggle, close).

  ## Assigns
    * `:current_session` - The current chat session (optional)
    * `:myself` - The parent LiveComponent CID (required)
    * `:fullscreen` - Whether the drawer is in fullscreen mode (default: false)
  """
  use LanglerWeb, :html

  def chat_header(assigns) do
    assigns =
      assigns
      |> assign_new(:current_session, fn -> nil end)
      |> assign_new(:fullscreen, fn -> false end)

    ~H"""
    <div class="chat-drawer-header">
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
          <h3 class="text-base font-semibold text-base-content">
            {if @current_session,
              do: @current_session.title || "New Chat",
              else: "Chat Assistant"}
          </h3>
        </div>
      </div>
      <div class="chat-drawer-actions">
        <button
          type="button"
          phx-click="toggle_keyboard"
          phx-target={@myself}
          class="btn btn-ghost btn-sm chat-pill-button"
        >
          <.icon name="hero-language" class="h-4 w-4" />
        </button>
        <button
          type="button"
          phx-click="toggle_fullscreen"
          phx-target={@myself}
          class="btn btn-ghost btn-sm btn-circle hidden lg:inline-flex"
          aria-label={if @fullscreen, do: "Exit fullscreen", else: "Enter fullscreen"}
        >
          <.icon
            name={if @fullscreen, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
            class="h-5 w-5"
          />
        </button>
        <button
          type="button"
          phx-click="toggle_chat"
          phx-target={@myself}
          class="btn btn-ghost btn-sm btn-circle"
          aria-label="Close chat"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </button>
      </div>
    </div>
    """
  end
end

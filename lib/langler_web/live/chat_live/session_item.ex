defmodule LanglerWeb.ChatLive.SessionItem do
  @moduledoc """
  Functional component for rendering a single chat session item in the sidebar.

  Displays the session title, date, rename form, and kebab menu.

  ## Assigns
    * `:session` - The ChatSession struct (required)
    * `:is_current` - Whether this is the current session (default: false)
    * `:is_renaming` - Whether in rename mode (default: false)
    * `:rename_value` - Current rename input value (default: "")
    * `:menu_open` - Whether menu is open (default: false)
    * `:myself` - Parent LiveComponent CID (required)
    * `:inserted_at` - Override for inserted_at date (optional)
  """
  use LanglerWeb, :html

  def session_item(assigns) do
    assigns =
      assigns
      |> assign_new(:is_current, fn -> false end)
      |> assign_new(:is_renaming, fn -> false end)
      |> assign_new(:rename_value, fn -> "" end)
      |> assign_new(:menu_open, fn -> false end)
      |> assign_new(:inserted_at, fn -> nil end)

    ~H"""
    <div class={[
      "group flex items-center gap-2 rounded-lg border border-base-300/70 bg-base-100 px-3 py-3 transition-all relative min-h-[4rem]",
      if(@is_current,
        do: "border-primary/50 bg-primary/5 shadow-sm",
        else: "hover:border-base-400"
      )
    ]}>
      <%= if @is_renaming do %>
        <form
          phx-submit="save_rename"
          phx-target={@myself}
          class="flex-1 flex items-center gap-2"
        >
          <input type="hidden" name="session-id" value={@session.id} />
          <input
            type="text"
            name="title"
            value={@rename_value || @session.title || ""}
            phx-blur="cancel_rename"
            phx-target={@myself}
            phx-keydown="cancel_rename"
            phx-key="Escape"
            class="input input-sm flex-1"
            autofocus
          />
        </form>
      <% else %>
        <button
          type="button"
          phx-click="switch_session"
          phx-value-session-id={@session.id}
          phx-target={@myself}
          class="flex-1 text-left min-w-0"
        >
          <p
            class="text-sm font-semibold text-base-content truncate"
            title={@session.title || "Untitled Chat"}
          >
            {@session.title || "Untitled Chat"}
          </p>
          <p class="text-xs text-base-content/60">
            {format_date(@inserted_at || @session.inserted_at)}
          </p>
        </button>
      <% end %>
      <div
        class="relative"
        id={"chat-menu-#{@session.id}"}
        phx-hook="ChatMenuDropdown"
        data-session-id={@session.id}
      >
        <button
          type="button"
          class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity"
          aria-label="Chat options"
          aria-expanded={if(@menu_open, do: "true", else: "false")}
          phx-click="toggle_chat_menu"
          phx-value-session-id={@session.id}
          phx-target={@myself}
        >
          <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
        </button>
        <ul
          :if={@menu_open}
          class="menu bg-base-100 rounded-box z-[100] w-52 p-2 shadow-lg border border-base-300"
          style="position: fixed;"
          phx-click-away="close_chat_menu"
          phx-target={@myself}
        >
          <li>
            <button
              type="button"
              phx-click="rename_session"
              phx-value-session-id={@session.id}
              phx-target={@myself}
            >
              <.icon name="hero-pencil" class="h-4 w-4" /> Rename
            </button>
          </li>
          <li>
            <button
              type="button"
              phx-click="toggle_pin_session"
              phx-value-session-id={@session.id}
              phx-target={@myself}
            >
              <.icon
                name={if(@session.pinned, do: "hero-pin-slash", else: "hero-pin")}
                class="h-4 w-4"
              />
              {if @session.pinned, do: "Unpin", else: "Pin"}
            </button>
          </li>
          <li>
            <button
              type="button"
              phx-click="delete_session"
              phx-value-session-id={@session.id}
              phx-target={@myself}
              class="text-error"
            >
              <.icon name="hero-trash" class="h-4 w-4" /> Delete
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
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
end

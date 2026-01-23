defmodule LanglerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use LanglerWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @dictionary_search_modal LanglerWeb.DictionarySearchLive.Modal

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign_new(assigns, :dictionary_search_modal, fn -> @dictionary_search_modal end)

    ~H"""
    <header class="primary-nav border-b border-base-200 bg-base-100/90 backdrop-blur sticky top-0 z-50 transition-all duration-200">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <.link
          navigate={~p"/articles"}
          class="flex items-center gap-3 text-lg font-semibold text-base-content no-underline"
        >
          <%!-- <img
            src={~p"/images/logo.svg"}
            width="36"
            height="36"
            alt="Langler logo"
            loading="eager"
            fetchpriority="high"
          /> --%>
          <span>Langler</span>
        </.link>

        <nav class="flex flex-wrap items-center gap-2 text-sm font-semibold text-base-content/80">
          <.link
            navigate={~p"/articles"}
            class="btn btn-ghost btn-sm rounded-full border border-transparent transition duration-200 hover:border-base-300 hover:bg-base-200/80 hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
          >
            Library
          </.link>
          <.link
            navigate={~p"/study"}
            class="btn btn-ghost btn-sm rounded-full border border-transparent transition duration-200 hover:border-base-300 hover:bg-base-200/80 hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
          >
            Study
          </.link>
        </nav>

        <div class="flex items-center gap-3">
          <.theme_toggle />
          <div :if={@current_scope} class="flex items-center gap-3">
            <div class="dropdown dropdown-end">
              <button
                type="button"
                class="btn btn-ghost btn-sm rounded-full border border-base-200 px-4 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/70 flex items-center gap-2"
                aria-label="Account menu"
              >
                {@current_scope.user.email}
                <span aria-hidden="true">▾</span>
              </button>
              <ul
                class="dropdown-content menu rounded-box w-48 border border-base-200 bg-base-100 shadow-2xl mt-2"
                role="menu"
              >
                <li role="none">
                  <.link
                    navigate={~p"/users/settings"}
                    class="text-base text-base-content/80 w-full px-4 py-2"
                    role="menuitem"
                  >
                    Settings
                  </.link>
                </li>
                <li role="none">
                  <.link
                    href={~p"/users/log-out"}
                    method="delete"
                    class="text-base text-base-content/80 w-full px-4 py-2"
                    role="menuitem"
                  >
                    Log out
                  </.link>
                </li>
              </ul>
            </div>
          </div>
          <div :if={is_nil(@current_scope)} class="flex items-center gap-2">
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
              Log in
            </.link>
            <.link navigate={~p"/users/register"} class="btn btn-sm btn-primary text-white">
              Create account
            </.link>
          </div>
        </div>
      </div>
    </header>

    <main class="app-main px-4 py-10 sm:px-6 lg:px-8">
      <div class="page-shell space-y-10">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />

    <%!-- Chat Drawer (only show for authenticated users) --%>
    <%= if @current_scope do %>
      <.live_component
        module={LanglerWeb.ChatLive.Drawer}
        id="chat-drawer"
        current_scope={@current_scope}
      />

      <%!-- Dictionary Search Modal (Cmd+J) --%>
      <.live_component
        module={@dictionary_search_modal}
        id="dictionary-search-modal"
        current_scope={@current_scope}
      />
    <% end %>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides theme toggle for Sage, Ocean, and Midnight themes.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm rounded-full">
        <.icon name="hero-swatch" class="h-5 w-5" />
        <span class="hidden sm:inline">Theme</span>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-100 rounded-box z-[1] w-48 border border-base-300 p-2 shadow-lg"
      >
        <li class="text-base-content">
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-theme="sage"
            class="flex items-center gap-2 w-full text-left hover:bg-base-200 active:bg-base-300"
            onclick="this.closest('.dropdown').removeAttribute('open')"
          >
            <span class="w-4 h-4 rounded-full bg-gradient-to-br from-teal-400 to-teal-600 shrink-0">
            </span>
            <span>Sage</span>
          </button>
        </li>
        <li class="text-base-content">
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-theme="ocean"
            class="flex items-center gap-2 w-full text-left hover:bg-base-200 active:bg-base-300"
            onclick="this.closest('.dropdown').removeAttribute('open')"
          >
            <span class="w-4 h-4 rounded-full bg-gradient-to-br from-blue-400 to-blue-600 shrink-0">
            </span>
            <span>Ocean</span>
          </button>
        </li>
        <li class="text-base-content">
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-theme="midnight"
            class="flex items-center gap-2 w-full text-left hover:bg-base-200 active:bg-base-300"
            onclick="this.closest('.dropdown').removeAttribute('open')"
          >
            <span class="w-4 h-4 rounded-full bg-gradient-to-br from-purple-600 to-purple-800 shrink-0">
            </span>
            <span>Midnight</span>
          </button>
        </li>
      </ul>
    </div>
    """
  end
end

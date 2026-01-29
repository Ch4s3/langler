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
  @allow_registration_link Application.compile_env(:langler, :env) != :prod
  @theme_options [
    %{name: "sage", label: "Sage", gradient: "from-teal-400 to-teal-600"},
    %{name: "ocean", label: "Ocean", gradient: "from-blue-400 to-blue-600"},
    %{name: "midnight", label: "Midnight", gradient: "from-purple-600 to-purple-800"}
  ]

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

  if @allow_registration_link do
    def app(assigns) do
      assigns =
        assigns
        |> assign_new(:dictionary_search_modal, fn -> @dictionary_search_modal end)
        |> assign_new(:allow_registration_link, fn -> @allow_registration_link end)

      app_with_registration(assigns)
    end

    defp app_with_registration(assigns) do
      ~H"""
      <header class="primary-nav border-b border-base-200 bg-base-100/90 backdrop-blur sticky top-0 z-50 transition-all duration-200">
        <div class="mx-auto grid w-full max-w-6xl grid-cols-[auto,1fr,auto] items-center gap-4 px-4 py-4 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/library"}
            class="flex items-center gap-3 text-lg font-semibold text-base-content no-underline"
          >
            <span class="hidden sm:inline">Langler</span>
          </.link>

          <nav class="flex min-w-0 justify-center">
            <ul class="flex w-full max-w-[26rem] items-center justify-center gap-1 rounded-full border border-base-200 bg-base-100/70 px-2 py-[0.35rem] text-xs font-semibold text-base-content/80 shadow-sm shadow-slate-900/10 sm:text-sm">
              <li class="rounded-full border border-transparent transition hover:border-base-300">
                <.link
                  navigate={~p"/library"}
                  class="flex items-center gap-2 rounded-full px-3 py-2 leading-none text-sm text-base-content/80 transition hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
                >
                  <.icon name="hero-book-open" class="h-4 w-4" />
                  <span>Library</span>
                </.link>
              </li>
              <li class="rounded-full border border-transparent transition hover:border-base-300">
                <.link
                  navigate={~p"/study"}
                  class="flex items-center gap-2 rounded-full px-3 py-2 leading-none text-sm text-base-content/80 transition hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
                >
                  <.icon name="hero-academic-cap" class="h-4 w-4" />
                  <span>Study</span>
                </.link>
              </li>
              <li :if={@current_scope} class="ml-auto flex items-center">
                <div class="dropdown dropdown-end">
                  <button
                    type="button"
                    tabindex="0"
                    class="btn btn-ghost btn-sm rounded-full border border-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/70 flex items-center gap-2"
                    aria-label={"Account menu for #{@current_scope.user.email}"}
                  >
                    <.icon name="hero-user-circle" class="h-5 w-5" />
                    <span class="sr-only">{@current_scope.user.email}</span>
                    <span aria-hidden="true">▾</span>
                  </button>
                  <ul
                    class="dropdown-content menu rounded-box w-56 border border-base-200 bg-base-100 shadow-2xl mt-2 space-y-1"
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
                    <li class="px-4 pt-3 text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-base-content/60">
                      Theme
                    </li>
                    <li class="px-4 pb-3">
                      <div class="flex flex-wrap items-center justify-center gap-2 lg:flex-col">
                        <%= for option <- theme_options() do %>
                          <button
                            type="button"
                            phx-click={JS.dispatch("phx:set-theme")}
                            data-theme={option.name}
                            class="flex h-10 w-10 items-center justify-center gap-3 rounded-lg border border-base-200 bg-base-100 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-base-content/80 transition hover:border-primary/60 hover:bg-base-200 focus-visible:ring focus-visible:ring-primary/30 lg:w-full lg:justify-between"
                            onclick="this.closest('.dropdown').removeAttribute('open')"
                          >
                            <span class={"h-6 w-6 aspect-square shrink-0 rounded-full bg-gradient-to-br #{option.gradient}"}>
                            </span>
                            <span class="hidden lg:inline text-[0.65rem]">{option.label}</span>
                            <span class="hidden lg:inline text-[0.5rem] text-base-content/50">
                              Apply
                            </span>
                          </button>
                        <% end %>
                      </div>
                    </li>
                  </ul>
                </div>
              </li>
            </ul>
          </nav>

          <div :if={is_nil(@current_scope)} class="flex items-center gap-2">
            <.theme_toggle />
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
              Log in
            </.link>
            <.link navigate="/users/register" class="btn btn-sm btn-primary text-white">
              Create account
            </.link>
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
  else
    def app(assigns) do
      assigns =
        assigns
        |> assign_new(:dictionary_search_modal, fn -> @dictionary_search_modal end)
        |> assign_new(:allow_registration_link, fn -> @allow_registration_link end)

      ~H"""
      <header class="primary-nav border-b border-base-200 bg-base-100/90 backdrop-blur sticky top-0 z-50 transition-all duration-200">
        <div class="mx-auto grid w-full max-w-6xl grid-cols-[auto,1fr,auto] items-center gap-4 px-4 py-4 sm:px-6 lg:px-8">
          <.link
            navigate={~p"/library"}
            class="flex items-center gap-3 text-lg font-semibold text-base-content no-underline"
          >
            <span class="hidden sm:inline">Langler</span>
          </.link>

          <nav class="flex min-w-0 justify-center">
            <ul class="flex w-full max-w-[26rem] items-center justify-center gap-1 rounded-full border border-base-200 bg-base-100/70 px-2 py-[0.35rem] text-xs font-semibold text-base-content/80 shadow-sm shadow-slate-900/10 sm:text-sm">
              <li class="rounded-full border border-transparent transition hover:border-base-300">
                <.link
                  navigate={~p"/library"}
                  class="flex items-center gap-2 rounded-full px-3 py-2 leading-none text-sm text-base-content/80 transition hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
                >
                  <.icon name="hero-book-open" class="h-4 w-4" />
                  <span>Library</span>
                </.link>
              </li>
              <li class="rounded-full border border-transparent transition hover:border-base-300">
                <.link
                  navigate={~p"/study"}
                  class="flex items-center gap-2 rounded-full px-3 py-2 leading-none text-sm text-base-content/80 transition hover:text-base-content focus-visible:ring focus-visible:ring-primary/40"
                >
                  <.icon name="hero-academic-cap" class="h-4 w-4" />
                  <span>Study</span>
                </.link>
              </li>
              <li :if={@current_scope} class="ml-auto flex items-center">
                <div class="dropdown dropdown-end">
                  <button
                    type="button"
                    tabindex="0"
                    class="btn btn-ghost btn-sm rounded-full border border-base-200 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-base-content/70 flex items-center gap-2"
                    aria-label={"Account menu for #{@current_scope.user.email}"}
                  >
                    <.icon name="hero-user-circle" class="h-5 w-5" />
                    <span class="sr-only">{@current_scope.user.email}</span>
                    <span aria-hidden="true">▾</span>
                  </button>
                  <ul
                    class="dropdown-content menu rounded-box w-56 border border-base-200 bg-base-100 shadow-2xl mt-2 space-y-1"
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
                    <li class="px-4 pt-3 text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-base-content/60">
                      Theme
                    </li>
                    <li class="px-4 pb-3">
                      <div class="flex flex-wrap items-center justify-center gap-2 lg:flex-col">
                        <%= for option <- theme_options() do %>
                          <button
                            type="button"
                            phx-click={JS.dispatch("phx:set-theme")}
                            data-theme={option.name}
                            class="flex h-10 w-10 items-center justify-center gap-3 rounded-lg border border-base-200 bg-base-100 px-3 py-2 text-xs font-semibold uppercase tracking-wide text-base-content/80 transition hover:border-primary/60 hover:bg-base-200 focus-visible:ring focus-visible:ring-primary/30 lg:w-full lg:justify-between"
                            onclick="this.closest('.dropdown').removeAttribute('open')"
                          >
                            <span class={"h-6 w-6 aspect-square shrink-0 rounded-full bg-gradient-to-br #{option.gradient}"}>
                            </span>
                            <span class="hidden lg:inline text-[0.65rem]">{option.label}</span>
                            <span class="hidden lg:inline text-[0.5rem] text-base-content/50">
                              Apply
                            </span>
                          </button>
                        <% end %>
                      </div>
                    </li>
                  </ul>
                </div>
              </li>
            </ul>
          </nav>

          <div :if={is_nil(@current_scope)} class="flex items-center gap-2">
            <.theme_toggle />
            <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
              Log in
            </.link>
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
        <%= for option <- theme_options() do %>
          <li class="text-base-content">
            <button
              type="button"
              phx-click={JS.dispatch("phx:set-theme")}
              data-theme={option.name}
              class="flex items-center gap-2 w-full text-left hover:bg-base-200 active:bg-base-300"
              onclick="this.closest('.dropdown').removeAttribute('open')"
            >
              <span class={"w-4 h-4 rounded-full bg-gradient-to-br #{option.gradient} shrink-0"}>
              </span>
              <span>{option.label}</span>
            </button>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  defp theme_options do
    @theme_options
  end
end

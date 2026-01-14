defmodule LanglerWeb.Admin.SourceSitesLive.Index do
  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.Workers.DiscoverArticlesWorker
  alias Oban

  def mount(_params, _session, socket) do
    source_sites = Content.list_source_sites()

    {:ok,
     socket
     |> assign(:source_sites, source_sites)
     |> assign(:form, to_form(%{}, as: :source_site))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-6xl space-y-6 px-4 py-8 sm:px-6 lg:px-0">
        <div class="flex items-center justify-between">
          <h1 class="text-3xl font-bold">Source Sites</h1>
          <.link
            navigate={~p"/admin/source-sites/new"}
            class="btn btn-primary"
            id="new-source-site"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
            New Source Site
          </.link>
        </div>

        <div class="overflow-x-auto">
          <table class="table table-zebra w-full" id="source-sites-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>URL</th>
                <th>Method</th>
                <th>Language</th>
                <th>Status</th>
                <th>Last Checked</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody id="source-sites" phx-update="stream">
              <tr :for={{id, source_site} <- @streams.source_sites} id={id}>
                <td><%= source_site.name %></td>
                <td>
                  <a href={source_site.url} target="_blank" class="link link-primary">
                    <%= source_site.url %>
                  </a>
                </td>
                <td>
                  <span class="badge badge-outline"><%= source_site.discovery_method %></span>
                </td>
                <td><%= source_site.language %></td>
                <td>
                  <span
                    class={[
                      "badge",
                      if(source_site.is_active, do: "badge-success", else: "badge-error")
                    ]}
                  >
                    <%= if source_site.is_active, do: "Active", else: "Inactive" %>
                  </span>
                  <%= if source_site.last_error do %>
                    <div class="tooltip tooltip-error" data-tip={source_site.last_error}>
                      <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-error" />
                    </div>
                  <% end %>
                </td>
                <td>
                  <%= if source_site.last_checked_at do %>
                    <%= Calendar.strftime(source_site.last_checked_at, "%Y-%m-%d %H:%M") %>
                  <% else %>
                    <span class="text-gray-400">Never</span>
                  <% end %>
                </td>
                <td>
                  <div class="flex gap-2">
                    <.link
                      navigate={~p"/admin/source-sites/#{source_site.id}/edit"}
                      class="btn btn-sm btn-ghost"
                      id={"edit-source-site-#{source_site.id}"}
                    >
                      <.icon name="hero-pencil" class="w-4 h-4" />
                    </.link>
                    <button
                      phx-click="run_discovery"
                      phx-value-id={source_site.id}
                      class="btn btn-sm btn-ghost"
                      id={"run-discovery-#{source_site.id}"}
                    >
                      <.icon name="hero-arrow-path" class="w-4 h-4" />
                    </button>
                    <button
                      phx-click="toggle_active"
                      phx-value-id={source_site.id}
                      class="btn btn-sm btn-ghost"
                      id={"toggle-active-#{source_site.id}"}
                    >
                      <.icon
                        name={if source_site.is_active, do: "hero-pause", else: "hero-play"}
                        class="w-4 h-4"
                      />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def handle_params(_params, _url, socket) do
    source_sites = Content.list_source_sites()

    {:noreply,
     socket
     |> stream(:source_sites, source_sites, reset: true)}
  end

  def handle_event("run_discovery", %{"id" => id}, socket) do
    source_site = Content.get_source_site!(id)

    %{"source_site_id" => source_site.id}
    |> DiscoverArticlesWorker.new(unique: [period: 300, keys: [:source_site_id]])
    |> Oban.insert()

    {:noreply,
     socket
     |> put_flash(:info, "Discovery queued for #{source_site.name}")}
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    source_site = Content.get_source_site!(id)

    case Content.update_source_site(source_site, %{is_active: !source_site.is_active}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> stream_insert(:source_sites, updated)
         |> put_flash(:info, "Source site #{if updated.is_active, do: "activated", else: "deactivated"}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update source site")}
    end
  end
end

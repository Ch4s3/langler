defmodule LanglerWeb.Admin.SourceSitesLive.Form do
  use LanglerWeb, :live_view

  alias Langler.Content
  alias Langler.Content.SourceSite

  def mount(params, _session, socket) do
    source_site =
      if params["id"] do
        Content.get_source_site!(params["id"])
      else
        %SourceSite{
          discovery_method: "rss",
          language: "spanish",
          is_active: true,
          check_interval_hours: 24
        }
      end

    {:ok,
     socket
     |> assign(:source_site, source_site)
     |> assign(:form, to_form(SourceSite.changeset(source_site, %{}), as: :source_site))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-3xl space-y-6 px-4 py-8 sm:px-6 lg:px-0">
        <h1 class="text-3xl font-bold">
          <%= if @source_site.id, do: "Edit Source Site", else: "New Source Site" %>
        </h1>

        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          id="source-site-form"
          class="space-y-6"
        >
          <.input
            field={@form[:name]}
            type="text"
            label="Name"
            placeholder="e.g., El País - Ciencia"
            required
          />

          <.input
            field={@form[:url]}
            type="text"
            label="Base URL"
            placeholder="https://elpais.com/ciencia"
            required
          />

          <.input
            field={@form[:language]}
            type="select"
            label="Language"
            options={[{"Spanish", "spanish"}, {"English", "english"}]}
            required
          />

          <.input
            field={@form[:discovery_method]}
            type="select"
            label="Discovery Method"
            options={[
              {"RSS Feed", "rss"},
              {"Web Scraping", "scraping"},
              {"Hybrid (RSS + Scraping)", "hybrid"}
            ]}
            required
          />

          <.input
            field={@form[:rss_url]}
            type="text"
            label="RSS Feed URL"
            placeholder="https://elpais.com/rss/ciencia.xml"
            phx-debounce="blur"
          />

          <div class="form-control">
            <label class="label">
              <span class="label-text">Scraping Config (JSON)</span>
            </label>
            <textarea
              name="source_site[scraping_config_json]"
              class="textarea textarea-bordered font-mono text-sm"
              rows="8"
              placeholder='{"list_selector": "article", "link_selector": "a[href]", "allow_patterns": ["/ciencia/"], "deny_patterns": []}'
              id="scraping-config-textarea"
            ><%= Jason.encode!(@source_site.scraping_config || %{}) %></textarea>
            <label class="label">
              <span class="label-text-alt">
                Optional: Configure selectors and URL patterns for web scraping
              </span>
            </label>
          </div>

          <.input
            field={@form[:check_interval_hours]}
            type="number"
            label="Check Interval (hours)"
            value={@source_site.check_interval_hours || 24}
            min="1"
            required
          />

          <.input
            field={@form[:is_active]}
            type="checkbox"
            label="Active"
            checked={@source_site.is_active}
          />

          <div class="flex gap-4">
            <.button type="submit" class="btn btn-primary" id="save-source-site">
              Save
            </.button>
            <.link navigate={~p"/admin/source-sites"} class="btn btn-ghost">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  def handle_event("validate", %{"source_site" => params}, socket) do
    scraping_config = parse_scraping_config(params["scraping_config_json"])

    attrs =
      params
      |> Map.put("scraping_config", scraping_config)
      |> Map.delete("scraping_config_json")

    changeset =
      socket.assigns.source_site
      |> SourceSite.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :source_site))}
  end

  def handle_event("save", %{"source_site" => params}, socket) do
    scraping_config = parse_scraping_config(params["scraping_config_json"])

    attrs =
      params
      |> Map.put("scraping_config", scraping_config)
      |> Map.delete("scraping_config_json")

    result =
      if socket.assigns.source_site.id do
        Content.update_source_site(socket.assigns.source_site, attrs)
      else
        Content.create_source_site(attrs)
      end

    case result do
      {:ok, _source_site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Source site saved successfully")
         |> push_navigate(to: ~p"/admin/source-sites")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :source_site))}
    end
  end

  defp parse_scraping_config(nil), do: %{}
  defp parse_scraping_config(""), do: %{}

  defp parse_scraping_config(json_string) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, config} when is_map(config) -> config
      _ -> %{}
    end
  end

  defp parse_scraping_config(_), do: %{}
end

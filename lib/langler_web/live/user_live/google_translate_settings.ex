defmodule LanglerWeb.UserLive.GoogleTranslateSettings do
  @moduledoc """
  LiveView for user Google Translate settings.
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts.GoogleTranslateConfig

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    configs = GoogleTranslateConfig.get_user_configs(scope.user.id)

    {:ok,
     socket
     |> assign(:configs, configs)
     |> assign(:editing_config, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl space-y-8 py-8">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-3xl font-bold text-base-content">Google Translate Settings</h1>
            <p class="mt-2 text-sm text-base-content/70">
              Configure your Google Translate API key for dictionary lookups and translations.
            </p>
          </div>
          <.link
            navigate={~p"/users/settings"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" /> Back to Settings
          </.link>
        </div>

        <%!-- List of existing configs --%>
        <div class="card border border-base-200 bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Your Google Translate Configuration</h2>

            <div :if={@configs == []} class="py-8 text-center">
              <.icon
                name="hero-language"
                class="mx-auto h-12 w-12 text-base-content/30"
              />
              <p class="mt-4 text-base-content/70">No Google Translate configuration yet.</p>
              <p class="text-sm text-base-content/50">Add your API key below to get started.</p>
            </div>

            <div :if={@configs != []} class="space-y-4">
              <div
                :for={config <- @configs}
                class="rounded-lg border border-base-200 bg-base-50 p-4"
              >
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <div class="flex items-center gap-2">
                      <h3 class="font-semibold text-base-content">Google Translate API</h3>
                      <span :if={config.is_default} class="badge badge-primary badge-sm">
                        Default
                      </span>
                      <span
                        :if={config.enabled}
                        class="badge badge-success badge-sm"
                      >
                        Enabled
                      </span>
                      <span :if={!config.enabled} class="badge badge-warning badge-sm">
                        Disabled
                      </span>
                    </div>
                    <dl class="mt-2 space-y-1 text-sm">
                      <div class="flex gap-2">
                        <dt class="font-medium text-base-content/70">API Key:</dt>
                        <dd class="font-mono text-base-content/60">
                          {GoogleTranslateConfig.decrypt_api_key_masked(
                            @current_scope.user.id,
                            config.encrypted_api_key
                          )}
                        </dd>
                      </div>
                    </dl>
                  </div>
                  <div class="flex gap-2">
                    <button
                      type="button"
                      class="btn btn-ghost btn-sm"
                      phx-click="edit_config"
                      phx-value-id={config.id}
                    >
                      <.icon name="hero-pencil" class="h-4 w-4" /> Edit
                    </button>
                    <button
                      type="button"
                      class="btn btn-error btn-sm"
                      phx-click="delete_config"
                      phx-value-id={config.id}
                      data-confirm="Are you sure you want to delete this configuration?"
                    >
                      <.icon name="hero-trash" class="h-4 w-4" /> Delete
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Add/Edit config form --%>
        <div class="card border border-base-200 bg-base-100 shadow-xl">
          <div class="card-body">
            <div class="flex items-center justify-between mb-4">
              <h2 class="card-title">
                {if @editing_config, do: "Edit Configuration", else: "Add New Configuration"}
              </h2>
            </div>

            <div class="rounded-lg border border-base-300 bg-base-200/50 p-4 mb-6">
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-information-circle"
                  class="h-5 w-5 flex-shrink-0 mt-0.5 text-primary"
                />
                <div class="flex-1">
                  <h3 class="font-semibold text-sm mb-1 text-base-content">
                    Need help getting your API key?
                  </h3>
                  <p class="text-sm text-base-content/80 mb-3">
                    You'll need a Google Cloud API key with the Cloud Translation API enabled.
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <.link
                      href="https://console.cloud.google.com/apis/credentials"
                      target="_blank"
                      class="btn btn-sm btn-primary"
                    >
                      <.icon name="hero-key" class="h-4 w-4" /> Get Google Cloud API Key
                    </.link>
                  </div>
                </div>
              </div>
            </div>

            <.form
              :let={f}
              for={@form || %{}}
              id="google-translate-config-form"
              phx-submit="save_config"
              phx-change="validate"
              class="space-y-4"
            >
              <.input
                field={f[:api_key]}
                type="text"
                label="API Key"
                placeholder="Enter your Google Cloud API key"
                required={is_nil(@editing_config)}
              />
              <p class="-mt-2 text-sm text-base-content/60">
                Your API key will be encrypted and stored securely. Get your key from
                <.link
                  href="https://console.cloud.google.com/apis/credentials"
                  target="_blank"
                  class="link link-primary"
                >
                  Google Cloud Console
                </.link>
              </p>

              <.input
                field={f[:is_default]}
                type="checkbox"
                label="Set as default configuration"
              />

              <.input
                field={f[:enabled]}
                type="checkbox"
                label="Enable Google Translate feature"
                value={get_field_value(f, :enabled, true)}
              />

              <div class="flex gap-2">
                <button type="submit" class="btn btn-primary">
                  <.icon name="hero-check" class="h-4 w-4" />
                  {if @editing_config, do: "Update", else: "Add"} Configuration
                </button>

                <button
                  :if={@editing_config}
                  type="button"
                  class="btn btn-ghost"
                  phx-click="cancel_edit"
                >
                  Cancel
                </button>

                <button
                  type="button"
                  class="btn btn-outline"
                  phx-click="test_config"
                  disabled={!can_test_config(@form)}
                >
                  <.icon name="hero-beaker" class="h-4 w-4" /> Test Connection
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"google_translate_config" => params}, socket) do
    form = to_form(params, as: :google_translate_config)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("validate", params, socket) when is_map(params) do
    form =
      params
      |> Map.drop(["_target"])
      |> Map.put_new("enabled", "true")
      |> Map.put_new("is_default", "false")

    {:noreply, assign(socket, :form, to_form(form, as: :google_translate_config))}
  end

  def handle_event("save_config", %{"google_translate_config" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.editing_config do
        config = socket.assigns.editing_config
        GoogleTranslateConfig.update_config(config, params)
      else
        GoogleTranslateConfig.create_config(scope.user, params)
      end

    case result do
      {:ok, _config} ->
        configs = GoogleTranslateConfig.get_user_configs(scope.user.id)

        {:noreply,
         socket
         |> assign(:configs, configs)
         |> assign(:editing_config, nil)
         |> assign(:form, nil)
         |> put_flash(:info, "Configuration saved successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to save configuration")
         |> assign(:form, to_form(changeset, as: :google_translate_config))}
    end
  end

  def handle_event("save_config", params, socket) when is_map(params) do
    handle_event("save_config", %{"google_translate_config" => params}, socket)
  end

  def handle_event("edit_config", %{"id" => id}, socket) do
    config = GoogleTranslateConfig.get_config(String.to_integer(id))

    form =
      to_form(
        %{
          "is_default" => config.is_default,
          "enabled" => config.enabled
        },
        as: :google_translate_config
      )

    {:noreply,
     socket
     |> assign(:editing_config, config)
     |> assign(:form, form)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_config, nil)
     |> assign(:form, nil)}
  end

  def handle_event("delete_config", %{"id" => id}, socket) do
    config = GoogleTranslateConfig.get_config(String.to_integer(id))
    scope = socket.assigns.current_scope

    case GoogleTranslateConfig.delete_config(config) do
      {:ok, _} ->
        configs = GoogleTranslateConfig.get_user_configs(scope.user.id)

        {:noreply,
         socket
         |> assign(:configs, configs)
         |> put_flash(:info, "Configuration deleted")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete configuration")}
    end
  end

  def handle_event("test_config", _, socket) do
    form = socket.assigns.form

    if form do
      params = form.params

      test_config = %{
        api_key: params["api_key"]
      }

      case GoogleTranslateConfig.test_config(test_config) do
        {:ok, message} ->
          {:noreply, put_flash(socket, :info, message)}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, put_flash(socket, :error, "Please fill in the form first")}
    end
  end

  defp can_test_config(nil), do: false

  defp can_test_config(form) do
    params = form.params
    api_key = params["api_key"]

    is_binary(api_key) and api_key != ""
  end

  defp get_field_value(f, field, default) do
    case f[field] do
      %Phoenix.HTML.FormField{value: value} when not is_nil(value) -> value
      _ -> default
    end
  end
end

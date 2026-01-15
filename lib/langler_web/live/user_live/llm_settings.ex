defmodule LanglerWeb.UserLive.LlmSettings do
  use LanglerWeb, :live_view

  alias Langler.Accounts.LlmConfig

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    configs = LlmConfig.get_user_configs(scope.user.id)
    providers = LlmConfig.list_providers()

    {:ok,
     socket
     |> assign(:configs, configs)
     |> assign(:providers, providers)
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
            <h1 class="text-3xl font-bold text-base-content">LLM Settings</h1>
            <p class="mt-2 text-sm text-base-content/70">
              Configure your AI provider API keys for the chat feature.
            </p>
          </div>
          <.link
            navigate={~p"/users/settings"}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-arrow-left" class="h-4 w-4" />
            Back to Settings
          </.link>
        </div>

        <%!-- List of existing configs --%>
        <div class="card border border-base-200 bg-base-100 shadow-xl">
          <div class="card-body">
            <h2 class="card-title">Your LLM Configurations</h2>

            <div :if={@configs == []} class="py-8 text-center">
              <.icon name="hero-chat-bubble-left-right" class="mx-auto h-12 w-12 text-base-content/30" />
              <p class="mt-4 text-base-content/70">No LLM configurations yet.</p>
              <p class="text-sm text-base-content/50">Add your first API key below to get started.</p>
            </div>

            <div :if={@configs != []} class="space-y-4">
              <div
                :for={config <- @configs}
                class="rounded-lg border border-base-200 bg-base-50 p-4"
              >
                <div class="flex items-start justify-between">
                  <div class="flex-1">
                    <div class="flex items-center gap-2">
                      <h3 class="font-semibold text-base-content">{provider_display_name(config.provider_name, @providers)}</h3>
                      <span :if={config.is_default} class="badge badge-primary badge-sm">Default</span>
                    </div>
                    <dl class="mt-2 space-y-1 text-sm">
                      <div class="flex gap-2">
                        <dt class="font-medium text-base-content/70">Model:</dt>
                        <dd class="text-base-content">{config.model || "default"}</dd>
                      </div>
                      <div class="flex gap-2">
                        <dt class="font-medium text-base-content/70">API Key:</dt>
                        <dd class="font-mono text-base-content/60">
                          {LlmConfig.decrypt_api_key_masked(@current_scope.user.id, config.encrypted_api_key)}
                        </dd>
                      </div>
                      <div class="flex gap-2">
                        <dt class="font-medium text-base-content/70">Temperature:</dt>
                        <dd class="text-base-content">{config.temperature}</dd>
                      </div>
                      <div class="flex gap-2">
                        <dt class="font-medium text-base-content/70">Max Tokens:</dt>
                        <dd class="text-base-content">{config.max_tokens}</dd>
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
                      <.icon name="hero-pencil" class="h-4 w-4" />
                      Edit
                    </button>
                    <button
                      type="button"
                      class="btn btn-error btn-sm"
                      phx-click="delete_config"
                      phx-value-id={config.id}
                      data-confirm="Are you sure you want to delete this configuration?"
                    >
                      <.icon name="hero-trash" class="h-4 w-4" />
                      Delete
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
            <h2 class="card-title">
              <%= if @editing_config, do: "Edit Configuration", else: "Add New Configuration" %>
            </h2>

            <.form
              :let={f}
              for={@form || %{}}
              id="llm-config-form"
              phx-submit="save_config"
              phx-change="validate"
              class="space-y-4"
            >
              <.input
                field={f[:provider_name]}
                type="select"
                label="Provider"
                options={Enum.map(@providers, fn p -> {p.display_name, p.name} end)}
                required
              />

              <.input
                field={f[:api_key]}
                type="text"
                label="API Key"
                placeholder="sk-..."
                required={is_nil(@editing_config)}
              />
              <p class="-mt-2 text-sm text-base-content/60">Your API key will be encrypted and stored securely</p>

              <.input
                field={f[:model]}
                type="text"
                label="Model (optional)"
                placeholder="gpt-4o-mini, gpt-4, etc."
              />
              <p class="-mt-2 text-sm text-base-content/60">Leave blank to use the default model</p>

              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={f[:temperature]}
                  type="number"
                  label="Temperature"
                  step="0.1"
                  min="0"
                  max="2"
                  value={get_field_value(f, :temperature, "0.7")}
                />

                <.input
                  field={f[:max_tokens]}
                  type="number"
                  label="Max Tokens"
                  min="100"
                  max="8000"
                  value={get_field_value(f, :max_tokens, "2000")}
                />
              </div>

              <.input
                field={f[:is_default]}
                type="checkbox"
                label="Set as default configuration"
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
                  disabled={get_field_value(f, :api_key, "") == ""}
                >
                  <.icon name="hero-beaker" class="h-4 w-4" />
                  Test Connection
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
  def handle_event("validate", %{"llm_config" => params}, socket) do
    form = to_form(params)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("validate", params, socket) when is_map(params) do
    form =
      params
      |> Map.drop(["_target", "_unused_provider_name", "_unused_api_key", "_unused_model", "_unused_temperature", "_unused_max_tokens"])
      |> Map.put_new("is_default", "false")

    {:noreply, assign(socket, :form, to_form(form))}
  end

  def handle_event("save_config", %{"llm_config" => params}, socket) do
    scope = socket.assigns.current_scope

    result =
      if socket.assigns.editing_config do
        config = socket.assigns.editing_config
        LlmConfig.update_config(config, params)
      else
        LlmConfig.create_config(scope.user, params)
      end

    case result do
      {:ok, _config} ->
        configs = LlmConfig.get_user_configs(scope.user.id)

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
         |> assign(:form, to_form(changeset))}
    end
  end

  def handle_event("save_config", params, socket) when is_map(params) do
    handle_event("save_config", %{"llm_config" => params}, socket)
  end

  def handle_event("edit_config", %{"id" => id}, socket) do
    config = LlmConfig.get_config(String.to_integer(id))

    form =
      to_form(%{
        "provider_name" => config.provider_name,
        "model" => config.model,
        "temperature" => config.temperature,
        "max_tokens" => config.max_tokens,
        "is_default" => config.is_default
      })

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
    config = LlmConfig.get_config(String.to_integer(id))
    scope = socket.assigns.current_scope

    case LlmConfig.delete_config(config) do
      {:ok, _} ->
        configs = LlmConfig.get_user_configs(scope.user.id)

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
        api_key: params["api_key"],
        model: params["model"] || "gpt-4o-mini",
        temperature: String.to_float(params["temperature"] || "0.7"),
        max_tokens: String.to_integer(params["max_tokens"] || "2000")
      }

      case LlmConfig.test_config(test_config) do
        {:ok, message} ->
          {:noreply, put_flash(socket, :info, message)}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply, put_flash(socket, :error, "Please fill in the form first")}
    end
  end

  defp provider_display_name(provider_name, providers) do
    case Enum.find(providers, fn p -> p.name == provider_name end) do
      nil -> provider_name
      provider -> provider.display_name
    end
  end

  defp get_field_value(form, field, default) do
    case form[field] do
      %Phoenix.HTML.FormField{value: value} when not is_nil(value) -> value
      _ -> default
    end
  end
end

defmodule LanglerWeb.OnboardingLive do
  use LanglerWeb, :live_view

  alias Langler.Accounts
  alias Langler.Languages

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.onboarding_completed?(socket.assigns.current_scope.user) do
      {:ok, push_navigate(socket, to: ~p"/library")}
    else
      {:ok,
       socket
       |> assign(:step, :select_languages)
       |> assign(:selected_languages, [])
       |> assign(:active_language, nil)
       |> assign(:ui_locale, "en")
       |> assign(:error, nil)}
    end
  end

  @impl true
  def handle_event("toggle_language", %{"code" => code}, socket) do
    selected = socket.assigns.selected_languages

    new_selected =
      if code in selected do
        List.delete(selected, code)
      else
        [code | selected]
      end

    {:noreply, assign(socket, selected_languages: new_selected, error: nil)}
  end

  def handle_event("continue_to_active", _params, socket) do
    if Enum.empty?(socket.assigns.selected_languages) do
      {:noreply, assign(socket, error: gettext("Please select at least one language to learn"))}
    else
      # Default to first selected language
      active = hd(socket.assigns.selected_languages)

      {:noreply,
       socket
       |> assign(:step, :set_active)
       |> assign(:active_language, active)
       |> assign(:error, nil)}
    end
  end

  def handle_event("set_active", %{"code" => code}, socket) do
    {:noreply, assign(socket, active_language: code, error: nil)}
  end

  def handle_event("continue_to_locale", _params, socket) do
    {:noreply, assign(socket, step: :set_locale, error: nil)}
  end

  def handle_event("set_ui_locale", %{"locale" => locale}, socket) do
    {:noreply, assign(socket, ui_locale: locale)}
  end

  def handle_event("match_ui_to_active", _params, socket) do
    locale = Languages.gettext_locale(socket.assigns.active_language)
    {:noreply, assign(socket, ui_locale: locale)}
  end

  def handle_event("complete", _params, socket) do
    user = socket.assigns.current_scope.user
    user_id = user.id

    case complete_onboarding_flow(user_id, user, socket.assigns) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Welcome! Your account is ready."))
         |> push_navigate(to: ~p"/library")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "#{reason}")}
    end
  end

  defp complete_onboarding_flow(user_id, user, assigns) do
    with :ok <- enable_selected_languages(user_id, assigns.selected_languages),
         {:ok, _} <- Accounts.set_active_language(user_id, assigns.active_language),
         {:ok, _} <- Accounts.upsert_user_preference(user, %{ui_locale: assigns.ui_locale}),
         {:ok, _} <- Accounts.complete_onboarding(user) do
      {:ok, :completed}
    else
      {:error, reason} -> {:error, "Failed: #{inspect(reason)}"}
    end
  end

  defp enable_selected_languages(user_id, language_codes) do
    results = Enum.map(language_codes, &Accounts.enable_language(user_id, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      {:error, reason} -> {:error, "Enable failed: #{inspect(reason)}"}
      nil -> :ok
    end
  end

  defp language_label(code) do
    case code do
      "pt-BR" -> "Português (BR)"
      "pt-PT" -> "Português (PT)"
      _ -> Languages.native_name(code)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="min-h-screen flex items-center justify-center bg-base-200 p-4"
      data-theme="ocean"
    >
      <div class="card w-full max-w-2xl section-card shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-3xl mb-6">{gettext("Welcome to Langler!")}</h2>

          <%= if @error do %>
            <div class="alert alert-error mb-4">
              <span>{@error}</span>
            </div>
          <% end %>

          <%= case @step do %>
            <% :select_languages -> %>
              <div>
                <h3 class="text-xl font-semibold mb-4">
                  {gettext("Which languages would you like to learn?")}
                </h3>
                <p class="text-sm text-base-content/70 mb-6">
                  {gettext(
                    "Select one or more languages. You can always add or remove languages later."
                  )}
                </p>

                <div class="grid grid-cols-2 md:grid-cols-3 gap-4 mb-6">
                  <%= for code <- Languages.study_language_codes() do %>
                    <button
                      type="button"
                      phx-click="toggle_language"
                      phx-value-code={code}
                      class={[
                        "btn btn-lg",
                        if(code in @selected_languages, do: "btn-primary", else: "btn-outline")
                      ]}
                    >
                      <span class="text-lg">{language_label(code)}</span>
                    </button>
                  <% end %>
                </div>

                <div class="card-actions justify-end">
                  <button
                    type="button"
                    phx-click="continue_to_active"
                    class="btn btn-primary"
                    disabled={Enum.empty?(@selected_languages)}
                  >
                    {gettext("Continue")}
                  </button>
                </div>
              </div>
            <% :set_active -> %>
              <div>
                <h3 class="text-xl font-semibold mb-4">
                  {gettext("Which language do you want to start with?")}
                </h3>
                <p class="text-sm text-base-content/70 mb-6">
                  {gettext(
                    "This will be your active language. You can switch between your languages anytime."
                  )}
                </p>

                <div class="space-y-3 mb-6">
                  <%= for code <- @selected_languages do %>
                    <label class="flex items-center gap-3 p-4 border rounded-lg cursor-pointer hover:bg-base-200 transition-colors">
                      <input
                        type="radio"
                        name="active_language"
                        value={code}
                        checked={code == @active_language}
                        phx-click="set_active"
                        phx-value-code={code}
                        class="radio radio-primary"
                      />
                      <span class="text-lg font-medium">{Languages.native_name(code)}</span>
                      <span class="text-sm text-base-content/60">
                        ({Languages.display_name(code)})
                      </span>
                    </label>
                  <% end %>
                </div>

                <div class="card-actions justify-end">
                  <button
                    type="button"
                    phx-click="continue_to_locale"
                    class="btn btn-primary"
                  >
                    {gettext("Continue")}
                  </button>
                </div>
              </div>
            <% :set_locale -> %>
              <div>
                <h3 class="text-xl font-semibold mb-4">
                  {gettext("Choose your interface language")}
                </h3>
                <p class="text-sm text-base-content/70 mb-6">
                  {gettext(
                    "This determines what language the app's buttons, menus, and messages appear in."
                  )}
                </p>

                <div class="form-control mb-4">
                  <label class="label">
                    <span class="label-text">{gettext("Interface Language")}</span>
                  </label>
                  <select
                    phx-change="set_ui_locale"
                    name="locale"
                    class="select select-bordered w-full"
                  >
                    <%= for code <- Languages.supported_codes() do %>
                      <option
                        value={Languages.gettext_locale(code)}
                        selected={Languages.gettext_locale(code) == @ui_locale}
                      >
                        {Languages.native_name(code)} ({Languages.display_name(code)})
                      </option>
                    <% end %>
                  </select>
                </div>

                <div class="mb-6">
                  <button
                    type="button"
                    phx-click="match_ui_to_active"
                    class="btn btn-sm btn-outline"
                  >
                    {gettext("Match UI to active language")} ({Languages.native_name(@active_language)})
                  </button>
                </div>

                <div class="card-actions justify-end">
                  <button
                    type="button"
                    phx-click="complete"
                    class="btn btn-primary"
                  >
                    {gettext("Complete Setup")}
                  </button>
                </div>
              </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

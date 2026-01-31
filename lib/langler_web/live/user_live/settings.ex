defmodule LanglerWeb.UserLive.Settings do
  @moduledoc """
  LiveView for user settings.
  """

  use LanglerWeb, :live_view

  on_mount {LanglerWeb.UserAuth, :require_sudo_mode}

  alias Langler.{Accounts, Content, Quizzes}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl space-y-8">
        <div class="text-center">
          <.header>
            Account Settings
            <:subtitle>Manage your account email address and password settings</:subtitle>
          </.header>
        </div>

        <%!-- Quick Settings Links --%>
        <div class="grid gap-4 md:grid-cols-2">
          <.link
            navigate={~p"/users/settings/llm"}
            class="card border border-base-200 bg-base-100 shadow-md transition-all duration-200 hover:-translate-y-1 hover:shadow-xl"
          >
            <div class="card-body flex flex-row items-center gap-4 p-4">
              <div class="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-primary/10">
                <.icon name="hero-chat-bubble-left-right" class="h-6 w-6 text-primary" />
              </div>
              <div class="flex-1 min-w-0">
                <h2 class="font-semibold text-base-content">AI Chat Settings</h2>
                <p class="text-sm text-base-content/60 truncate">
                  Configure LLM provider and API keys
                </p>
              </div>
              <.icon name="hero-chevron-right" class="h-5 w-5 flex-shrink-0 text-base-content/40" />
            </div>
          </.link>

          <.link
            navigate={~p"/users/settings/tts"}
            class="card border border-base-200 bg-base-100 shadow-md transition-all duration-200 hover:-translate-y-1 hover:shadow-xl"
          >
            <div class="card-body flex flex-row items-center gap-4 p-4">
              <div class="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-accent/10">
                <.icon name="hero-speaker-wave" class="h-6 w-6 text-accent" />
              </div>
              <div class="flex-1 min-w-0">
                <h2 class="font-semibold text-base-content">TTS Settings</h2>
                <p class="text-sm text-base-content/60 truncate">
                  Configure Text-to-Speech provider for listening
                </p>
              </div>
              <.icon name="hero-chevron-right" class="h-5 w-5 flex-shrink-0 text-base-content/40" />
            </div>
          </.link>

          <.link
            navigate={~p"/users/settings/google-translate"}
            class="card border border-base-200 bg-base-100 shadow-md transition-all duration-200 hover:-translate-y-1 hover:shadow-xl"
          >
            <div class="card-body flex flex-row items-center gap-4 p-4">
              <div class="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-secondary/10">
                <.icon name="hero-language" class="h-6 w-6 text-secondary" />
              </div>
              <div class="flex-1 min-w-0">
                <h2 class="font-semibold text-base-content">Google Translate Settings</h2>
                <p class="text-sm text-base-content/60 truncate">
                  Configure Google Translate API key for dictionary lookups
                </p>
              </div>
              <.icon name="hero-chevron-right" class="h-5 w-5 flex-shrink-0 text-base-content/40" />
            </div>
          </.link>
        </div>

        <%!-- Dictionary Preferences --%>
        <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-4">
          <div class="flex items-center gap-3">
            <div class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-info/10">
              <.icon name="hero-book-open" class="h-5 w-5 text-info" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-base-content">Dictionary Preferences</h2>
              <p class="text-sm text-base-content/60">Configure how word definitions are looked up</p>
            </div>
          </div>

          <div class="divider my-2"></div>

          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-4">
              <input
                type="checkbox"
                id="use-llm-for-definitions"
                class="toggle toggle-primary"
                checked={@use_llm_for_definitions}
                phx-click="toggle_llm_definitions"
              />
              <div>
                <span class="label-text font-medium">Use AI for definitions</span>
                <p class="text-xs text-base-content/60 mt-0.5">
                  Use your configured LLM (instead of Google Translate) for word definitions.
                  Useful for testing or if Google Translate is not configured.
                </p>
              </div>
            </label>
          </div>

          <div :if={@use_llm_for_definitions && !@has_llm_config} class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
            <span>No LLM configuration found. Please configure your AI Chat settings first.</span>
          </div>

          <div :if={@use_llm_for_definitions && @has_llm_config} class="alert alert-info">
            <.icon name="hero-information-circle" class="h-5 w-5" />
            <span>Word definitions will use your configured LLM provider.</span>
          </div>
        </div>

        <%!-- Article Processing --%>
        <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-4">
          <div class="flex items-center gap-3">
            <div class="flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full bg-primary/10">
              <.icon name="hero-document-text" class="h-5 w-5 text-primary" />
            </div>
            <div>
              <h2 class="text-lg font-semibold text-base-content">Article Processing</h2>
              <p class="text-sm text-base-content/60">Options when importing articles</p>
            </div>
          </div>

          <div class="divider my-2"></div>

          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-4">
              <input
                type="checkbox"
                id="auto-detect-idioms"
                class="toggle toggle-primary"
                checked={@auto_detect_idioms}
                phx-click="toggle_idiom_detection"
              />
              <div>
                <span class="label-text font-medium">Auto-detect idioms in articles</span>
                <p class="text-xs text-base-content/60 mt-0.5">
                  Use AI to identify idioms and expressions when importing articles.
                  Requires an LLM provider to be configured.
                </p>
              </div>
            </label>
          </div>

          <div :if={@auto_detect_idioms && !@has_llm_config} class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
            <span>No LLM configuration found. Please configure your AI Chat settings first.</span>
          </div>

          <div :if={@auto_detect_idioms && @has_llm_config} class="alert alert-info">
            <.icon name="hero-information-circle" class="h-5 w-5" />
            <span>Idioms will be detected when you import new articles.</span>
          </div>
        </div>

        <%!-- Account Details --%>
        <div class="grid gap-8 lg:grid-cols-2">
          <div class="space-y-8">
            <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-4">
              <h2 class="text-lg font-semibold text-base-content">Email</h2>
              <.form
                for={@email_form}
                id="email_form"
                phx-submit="update_email"
                phx-change="validate_email"
                class="space-y-4"
              >
                <.input
                  field={@email_form[:email]}
                  type="email"
                  label="Email"
                  autocomplete="username"
                  required
                />
                <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
              </.form>
            </div>

            <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-4">
              <h2 class="text-lg font-semibold text-base-content">Password</h2>
              <.form
                for={@password_form}
                id="password_form"
                action={~p"/users/update-password"}
                method="post"
                phx-change="validate_password"
                phx-submit="update_password"
                phx-trigger-action={@trigger_submit}
                class="space-y-4"
              >
                <input
                  name={@password_form[:email].name}
                  type="hidden"
                  id="hidden_user_email"
                  autocomplete="username"
                  value={@current_email}
                />
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="New password"
                  autocomplete="new-password"
                  required
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirm new password"
                  autocomplete="new-password"
                />
                <.button variant="primary" phx-disable-with="Saving...">Save Password</.button>
              </.form>
            </div>
          </div>

          <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                  Archived articles
                </p>
                <p class="text-base text-base-content">
                  Restore or permanently delete saved articles
                </p>
              </div>
              <span class="badge badge-outline">{length(@archived_articles)}</span>
            </div>

            <div
              :if={@archived_articles == []}
              class="rounded-2xl border border-dashed border-base-300 p-6 text-center text-base-content/70"
            >
              No archived articles yet.
            </div>

            <div
              :for={article <- @archived_articles}
              class="rounded-2xl border border-base-200 bg-base-100/80 p-4 space-y-3"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p class="text-lg font-semibold text-base-content">{article.title}</p>
                  <p class="text-xs uppercase tracking-wide text-base-content/50">
                    {article.source || URI.parse(article.url).host}
                  </p>
                  <p class="text-xs text-base-content/60">
                    Imported {format_timestamp(article.inserted_at)}
                  </p>
                </div>
                <div class="flex gap-2">
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="restore_article"
                    phx-value-id={article.id}
                  >
                    Restore
                  </button>
                  <button
                    class="btn btn-xs btn-error text-white"
                    phx-click="delete_article"
                    phx-value-id={article.id}
                    phx-confirm="Delete this article permanently?"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">
                  Finished articles
                </p>
                <p class="text-base text-base-content">
                  Articles you've completed with quiz scores
                </p>
              </div>
              <span class="badge badge-outline">{length(@finished_articles)}</span>
            </div>

            <div
              :if={@finished_articles == []}
              class="rounded-2xl border border-dashed border-base-300 p-6 text-center text-base-content/70"
            >
              No finished articles yet.
            </div>

            <div
              :for={article_data <- @finished_articles}
              class="rounded-2xl border border-base-200 bg-base-100/80 p-4 space-y-3"
            >
              <% article = article_data.article %>
              <% best_attempt = article_data.best_attempt %>
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="flex-1">
                  <p class="text-lg font-semibold text-base-content">{article.title}</p>
                  <p class="text-xs uppercase tracking-wide text-base-content/50">
                    {article.source || URI.parse(article.url).host}
                  </p>
                  <p class="text-xs text-base-content/60">
                    Imported {format_timestamp(article.inserted_at)}
                  </p>
                </div>
                <div class="flex items-center gap-3">
                  <div class="flex items-center gap-2">
                    <span
                      :if={best_attempt}
                      class="badge badge-primary badge-lg"
                    >
                      {best_attempt.score}/{best_attempt.max_score}
                    </span>
                    <span
                      :if={!best_attempt}
                      class="badge badge-ghost badge-lg"
                    >
                      No quiz
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <.link
                      :if={best_attempt}
                      navigate={~p"/articles/#{article.id}?quiz=1"}
                      class="btn btn-xs btn-primary"
                    >
                      Retake quiz
                    </.link>
                    <button
                      class="btn btn-xs btn-ghost"
                      phx-click="restore_finished_article"
                      phx-value-id={article.id}
                    >
                      Restore
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    archived = Content.list_archived_articles_for_user(user.id)
    finished = load_finished_articles_with_scores(user.id)

    # Load dictionary and article processing preferences
    user_pref = Accounts.get_user_preference(user.id)
    use_llm_for_definitions = user_pref && user_pref.use_llm_for_definitions
    auto_detect_idioms = user_pref && user_pref.auto_detect_idioms
    has_llm_config = Accounts.LlmConfig.get_default_config(user.id) != nil

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:archived_articles, archived)
      |> assign(:finished_articles, finished)
      |> assign(:use_llm_for_definitions, use_llm_for_definitions || false)
      |> assign(:auto_detect_idioms, auto_detect_idioms || false)
      |> assign(:has_llm_config, has_llm_config)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("restore_article", %{"id" => id}, socket) do
    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <-
           Content.restore_article_for_user(socket.assigns.current_scope.user.id, article_id) do
      {:noreply,
       assign(socket, :archived_articles, fetch_archived(socket.assigns.current_scope.user.id))}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to restore: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_article", %{"id" => id}, socket) do
    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <-
           Content.delete_article_for_user(socket.assigns.current_scope.user.id, article_id) do
      {:noreply,
       socket
       |> assign(:archived_articles, fetch_archived(socket.assigns.current_scope.user.id))
       |> put_flash(:info, "Article permanently removed")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to delete: #{inspect(reason)}")}
    end
  end

  def handle_event("restore_finished_article", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <- Content.restore_article_for_user(user_id, article_id) do
      {:noreply,
       socket
       |> assign(:finished_articles, load_finished_articles_with_scores(user_id))
       |> put_flash(:info, "Article restored")}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to restore: #{inspect(reason)}")}
    end
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("toggle_llm_definitions", _params, socket) do
    user = socket.assigns.current_scope.user
    new_value = !socket.assigns.use_llm_for_definitions

    case Accounts.upsert_user_preference(user, %{use_llm_for_definitions: new_value}) do
      {:ok, _pref} ->
        {:noreply,
         socket
         |> assign(:use_llm_for_definitions, new_value)
         |> put_flash(:info, "Dictionary preference updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  def handle_event("toggle_idiom_detection", _params, socket) do
    user = socket.assigns.current_scope.user
    new_value = !socket.assigns.auto_detect_idioms

    case Accounts.upsert_user_preference(user, %{auto_detect_idioms: new_value}) do
      {:ok, _pref} ->
        {:noreply,
         socket
         |> assign(:auto_detect_idioms, new_value)
         |> put_flash(:info, "Article processing preference updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp fetch_archived(user_id), do: Content.list_archived_articles_for_user(user_id)

  defp load_finished_articles_with_scores(user_id) do
    finished_articles = Content.list_finished_articles_for_user(user_id)
    article_ids = Enum.map(finished_articles, & &1.id)

    # Batch load all best attempts in a single query
    best_attempts = Quizzes.best_attempts_for_articles(user_id, article_ids)
    attempt_map = Map.new(best_attempts, &{&1.article_id, &1})

    Enum.map(finished_articles, fn article ->
      %{
        article: article,
        best_attempt: Map.get(attempt_map, article.id)
      }
    end)
  end

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}
end

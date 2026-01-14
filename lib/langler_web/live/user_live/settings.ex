defmodule LanglerWeb.UserLive.Settings do
  use LanglerWeb, :live_view

  on_mount {LanglerWeb.UserAuth, :require_sudo_mode}

  alias Langler.{Accounts, Content}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <div class="grid gap-8 lg:grid-cols-2">
        <div class="space-y-8">
          <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-4">
            <h2 class="text-lg font-semibold text-base-content">Email</h2>
            <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email" class="space-y-4">
              <.input field={@email_form[:email]} type="email" label="Email" autocomplete="username" required />
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
              <.input field={@password_form[:password]} type="password" label="New password" autocomplete="new-password" required />
              <.input field={@password_form[:password_confirmation]} type="password" label="Confirm new password" autocomplete="new-password" />
              <.button variant="primary" phx-disable-with="Saving...">Save Password</.button>
            </.form>
          </div>
        </div>

        <div class="rounded-3xl border border-base-200 bg-base-100/90 p-6 space-y-6">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-semibold uppercase tracking-widest text-base-content/60">Archived articles</p>
              <p class="text-base text-base-content">Restore or permanently delete saved articles</p>
            </div>
            <span class="badge badge-outline">{length(@archived_articles)}</span>
          </div>

          <div :if={@archived_articles == []} class="rounded-2xl border border-dashed border-base-300 p-6 text-center text-base-content/70">
            No archived articles yet.
          </div>

          <div :for={article <- @archived_articles} class="rounded-2xl border border-base-200 bg-base-100/80 p-4 space-y-3">
            <div class="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p class="text-lg font-semibold text-base-content">{article.title}</p>
                <p class="text-xs uppercase tracking-wide text-base-content/50">{article.source || URI.parse(article.url).host}</p>
                <p class="text-xs text-base-content/60">Imported {format_timestamp(article.inserted_at)}</p>
              </div>
              <div class="flex gap-2">
                <button class="btn btn-xs btn-ghost" phx-click="restore_article" phx-value-id={article.id}>
                  Restore
                </button>
                <button class="btn btn-xs btn-error text-white" phx-click="delete_article" phx-value-id={article.id} phx-confirm="Delete this article permanently?">
                  Delete
                </button>
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

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:archived_articles, archived)

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
         {:ok, _} <- Content.restore_article_for_user(socket.assigns.current_scope.user.id, article_id) do
      {:noreply, assign(socket, :archived_articles, fetch_archived(socket.assigns.current_scope.user.id))}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Unable to restore: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_article", %{"id" => id}, socket) do
    with {:ok, article_id} <- parse_id(id),
         {:ok, _} <- Content.delete_article_for_user(socket.assigns.current_scope.user.id, article_id) do
      {:noreply,
       socket
       |> assign(:archived_articles, fetch_archived(socket.assigns.current_scope.user.id))
       |> put_flash(:info, "Article permanently removed")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Unable to delete: #{inspect(reason)}")}
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
  defp format_timestamp(nil), do: "recently"

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp fetch_archived(user_id), do: Content.list_archived_articles_for_user(user_id)

  defp parse_id(value) when is_integer(value), do: {:ok, value}

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp parse_id(_), do: {:error, :invalid_id}
end

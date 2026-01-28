defmodule LanglerWeb.UserLive.Registration do
  @moduledoc """
  LiveView for user registration (invite-only).
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts
  alias Langler.Accounts.{Invites, User}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <%= if @invite_valid do %>
          <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              autocomplete="username"
              required
              phx-mounted={JS.focus()}
            />

            <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
              Create an account
            </.button>
          </.form>
        <% else %>
          <div class="alert alert-error">
            <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
            <span>
              <%= if @invite_error do %>
                {@invite_error}
              <% else %>
                Invalid or expired invitation link. Please request a new invite.
              <% end %>
            </span>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: LanglerWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(%{"token" => token}, _session, socket) do
    case Invites.get_valid_invite_by_token(token) do
      nil ->
        {:ok,
         socket
         |> assign(:invite_valid, false)
         |> assign(:invite_error, "Invalid or expired invitation link.")
         |> assign(:invite_token, token)
         |> assign(:invite_email, nil)
         |> assign_form(%User{}, %{})}

      invite ->
        changeset = Accounts.change_user_email(%User{}, %{email: invite.email}, validate_unique: false)

        {:ok,
         socket
         |> assign(:invite_valid, true)
         |> assign(:invite_token, token)
         |> assign(:invite_email, invite.email)
         |> assign(:invite, invite)
         |> assign_form(changeset),
         temporary_assigns: [form: nil]}
    end
  end

  def mount(_params, _session, socket) do
    # No token provided - redirect or show error
    {:ok,
     socket
     |> assign(:invite_valid, false)
     |> assign(:invite_error, "An invitation token is required to register.")
     |> assign(:invite_token, nil)
     |> assign(:invite_email, nil)
     |> assign_form(%User{}, %{})}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    if socket.assigns.invite_valid do
      handle_valid_invite(socket, user_params)
    else
      {:noreply,
       socket
       |> put_flash(:error, "Invalid invitation. Please use a valid invite link.")
       |> assign_form(
         Accounts.change_user_email(%User{}, user_params, validate_unique: false)
       )}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    # Ensure email matches invite if set
    email = socket.assigns.invite_email || user_params["email"]
    changeset = Accounts.change_user_email(%User{}, %{email: email}, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp handle_valid_invite(socket, user_params) do
    email = user_params["email"]

    case Accounts.register_user(%{email: email}) do
      {:ok, user} ->
        handle_successful_registration(socket, user, email)

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp handle_successful_registration(socket, user, email) do
    case Invites.use_invite(socket.assigns.invite, user) do
      {:ok, _invite} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, _} ->

        {:noreply,
         socket
         |> put_flash(:error, "Failed to process invitation. Please try again.")
         |> assign_form(Accounts.change_user_email(%User{}, %{email: email}, validate_unique: false))}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end

  defp assign_form(socket, %User{} = user, attrs) do
    changeset = Accounts.change_user_email(user, attrs, validate_unique: false)
    assign_form(socket, changeset)
  end
end

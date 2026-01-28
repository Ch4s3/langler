defmodule LanglerWeb.UserLive.Invites do
  @moduledoc """
  LiveView for managing user invites.
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts
  alias Langler.Accounts.{Invites, UserInvite}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    invites = Invites.list_sent_invites(user)
    can_send = Invites.can_send_invite?(user)

    {:ok,
     socket
     |> assign(:invites, invites)
     |> assign(:can_send, can_send)
     |> assign(:invites_remaining, user.invites_remaining)
     |> assign(:is_admin, user.is_admin)
     |> assign_form(%{"email" => ""})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl space-y-8">
        <div class="text-center">
          <.header>
            Invite Friends
            <:subtitle>
              <%= if @is_admin do %>
                You're an admin - you have unlimited invites!
              <% else %>
                You have {@invites_remaining} invite{if @invites_remaining != 1, do: "s", else: ""} remaining
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <%!-- Send Invite Form --%>
        <%= if @can_send do %>
          <div class="card border border-base-200 bg-base-100 shadow-md">
            <div class="card-body">
              <h2 class="card-title mb-4">Send an Invite</h2>
              <.form for={@form} id="invite-form" phx-submit="send_invite" phx-change="validate">
                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email address"
                  placeholder="friend@example.com"
                  required
                  autocomplete="email"
                />

                <.button phx-disable-with="Sending..." class="btn btn-primary w-full">
                  Send Invite
                </.button>
              </.form>
            </div>
          </div>
        <% else %>
          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="h-6 w-6" />
            <span>You've used all your invites. Contact an admin if you need more.</span>
          </div>
        <% end %>

        <%!-- Invites List --%>
        <div class="card border border-base-200 bg-base-100 shadow-md">
          <div class="card-body">
            <h2 class="card-title mb-4">Sent Invites</h2>
            <%= if @invites == [] do %>
              <p class="text-base-content/60">You haven't sent any invites yet.</p>
            <% else %>
              <div class="overflow-x-auto">
                <table class="table">
                  <thead>
                    <tr>
                      <th>Email</th>
                      <th>Status</th>
                      <th>Sent</th>
                      <th>Expires</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={invite <- @invites}>
                      <td>{invite.email}</td>
                      <td>
                        <%= cond do %>
                          <% UserInvite.used?(invite) -> %>
                            <span class="badge badge-success">Used</span>
                          <% UserInvite.expired?(invite) -> %>
                            <span class="badge badge-error">Expired</span>
                          <% true -> %>
                            <span class="badge badge-warning">Pending</span>
                        <% end %>
                      </td>
                      <td>
                        {Calendar.strftime(invite.inserted_at, "%b %d, %Y")}
                      </td>
                      <td>
                        {Calendar.strftime(invite.expires_at, "%b %d, %Y")}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"email" => email}, socket) do
    changeset =
      {%{}, %{email: :string}}
      |> Ecto.Changeset.cast(%{"email" => email}, [:email])
      |> Ecto.Changeset.validate_required([:email])
      |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> Ecto.Changeset.validate_length(:email, max: 160)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("send_invite", %{"email" => email}, socket) do
    user = socket.assigns.current_scope.user

    case Invites.create_invite(user, email) do
      {:ok, invite} ->
        # Send the invite email
        invite_url = url(~p"/users/register/#{invite.token}")
        Accounts.UserNotifier.deliver_invitation_email(user.email, email, invite_url)

        # Reload user to get updated invites_remaining
        updated_user = Accounts.get_user!(user.id)
        invites = Invites.list_sent_invites(updated_user)

        {:noreply,
         socket
         |> put_flash(:info, "Invite sent to #{email}!")
         |> assign(:invites, invites)
         |> assign(:invites_remaining, updated_user.invites_remaining)
         |> assign(:can_send, Invites.can_send_invite?(updated_user))
         |> assign_form(%{"email" => ""})}

      {:error, :no_invites_remaining} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have any invites remaining.")
         |> assign(:can_send, false)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "invite")
    assign(socket, form: form)
  end

  defp assign_form(socket, attrs) when is_map(attrs) do
    # Create a simple changeset for email validation
    changeset =
      {%{}, %{email: :string}}
      |> Ecto.Changeset.cast(attrs, [:email])
      |> Ecto.Changeset.validate_required([:email])
      |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> Ecto.Changeset.validate_length(:email, max: 160)

    assign_form(socket, changeset)
  end
end

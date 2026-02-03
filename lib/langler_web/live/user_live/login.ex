defmodule LanglerWeb.UserLive.Login do
  @moduledoc """
  LiveView for user login.
  """

  use LanglerWeb, :live_view

  alias Langler.Accounts

  @allow_registration_link Application.compile_env(:langler, :env) != :prod

  if @allow_registration_link do
    @impl true
    def render(assigns) do
      render_with_registration(assigns)
    end

    defp render_with_registration(assigns) do
      ~H"""
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <div class="mx-auto max-w-sm space-y-4">
          <div class="text-center">
            <.header>
              <p>{gettext("Log in")}</p>
              <:subtitle>
                <%= if @current_scope do %>
                  {gettext("You need to reauthenticate to perform sensitive actions on your account.")}
                <% else %>
                  {gettext("Don't have an account?")} <.link
                    navigate="/users/register"
                    class="font-semibold text-brand hover:underline"
                    phx-no-format
                  >{gettext("Sign up")}</.link> {gettext("for an account now.")}.
                <% end %>
              </:subtitle>
            </.header>
          </div>

          <div :if={local_mail_adapter?()} class="alert alert-info">
            <.icon name="hero-information-circle" class="size-6 shrink-0" />
            <div>
              <p>You are running the local mail adapter.</p>
              <p>
                To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
              </p>
            </div>
          </div>

          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
          >
            <input type="hidden" name="user[magic]" value="true" />
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="email"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full">
              Log in with email <span aria-hidden="true">→</span>
            </.button>
            <p class="text-sm text-gray-500 mt-2">
              We’ll email a secure link so you can log in without a password.
            </p>
          </.form>

          <div class="divider">{gettext("or")}</div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="email"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
            />
            <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
              {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
            </.button>
            <.button class="btn btn-primary btn-soft w-full mt-2">
              Log in only this time
            </.button>
          </.form>
        </div>
      </Layouts.app>
      """
    end
  else
    @impl true
    def render(assigns) do
      ~H"""
      <Layouts.app flash={@flash} current_scope={@current_scope}>
        <div class="mx-auto max-w-sm space-y-4">
          <div class="text-center">
            <.header>
              <p>Log in</p>
              <:subtitle>
                <%= if @current_scope do %>
                  You need to reauthenticate to perform sensitive actions on your account.
                <% end %>
              </:subtitle>
            </.header>
          </div>

          <div :if={local_mail_adapter?()} class="alert alert-info">
            <.icon name="hero-information-circle" class="size-6 shrink-0" />
            <div>
              <p>You are running the local mail adapter.</p>
              <p>
                To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
              </p>
            </div>
          </div>

          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log-in"}
            phx-submit="submit_magic"
          >
            <input type="hidden" name="user[magic]" value="true" />
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="email"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full">
              Log in with email <span aria-hidden="true">→</span>
            </.button>
            <p class="text-sm text-gray-500 mt-2">
              We'll email a secure link so you can log in without a password.
            </p>
          </.form>

          <div class="divider">{gettext("or")}</div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="email"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
            />
            <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
              {gettext("Log in and stay logged in")} <span aria-hidden="true">→</span>
            </.button>
            <.button class="btn btn-primary btn-soft w-full mt-2">
              Log in only this time
            </.button>
          </.form>
        </div>
      </Layouts.app>
      """
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       form: form,
       trigger_submit: false,
       allow_registration_link: @allow_registration_link
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      gettext(
        "If your email is in our system, you will receive instructions for logging in shortly."
      )

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:langler, Langler.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end

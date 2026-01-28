defmodule Langler.Accounts.UserNotifier do
  @moduledoc """
  Email notifications for user account events.
  """

  import Swoosh.Email

  alias Langler.Accounts.User
  alias Langler.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from_email = get_from_email()

    email =
      new()
      |> to(recipient)
      |> from({"Langler", from_email})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # Gets the from email address based on the configured mailer domain
  # Uses the Mailgun domain if configured, otherwise falls back to example.com
  defp get_from_email do
    case Application.get_env(:langler, Langler.Mailer, []) do
      config when is_list(config) ->
        case Keyword.get(config, :domain) do
          nil -> "contact@example.com"
          domain -> "postmaster@#{domain}"
        end

      _ ->
        "contact@example.com"
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver an invitation email with the invite link.
  """
  def deliver_invitation_email(inviter_email, invitee_email, invite_url) do
    deliver(invitee_email, "You've been invited to Langler", """

    ==============================

    Hi,

    #{inviter_email} has invited you to join Langler!

    Click the link below to create your account:

    #{invite_url}

    This invitation will expire in 7 days.

    If you didn't expect this invitation, you can safely ignore this email.

    ==============================
    """)
  end
end

defmodule Langler.Accounts.Invites do
  @moduledoc """
  Context for managing user invites.
  """

  import Ecto.Query, warn: false
  alias Langler.Accounts.{User, UserInvite}
  alias Langler.Repo

  @invite_expiration_days 7

  @doc """
  Checks if a user can send an invite.
  Admins have unlimited invites, regular users need invites_remaining > 0.
  """
  def can_send_invite?(%User{is_admin: true}), do: true
  def can_send_invite?(%User{invites_remaining: remaining}) when remaining > 0, do: true
  def can_send_invite?(_), do: false

  @doc """
  Creates a new invite for the given inviter and email.
  Returns {:ok, invite} or {:error, changeset}.
  """
  def create_invite(%User{} = inviter, email) when is_binary(email) do
    if can_send_invite?(inviter) do
      token = generate_token()
      expires_at = DateTime.utc_now() |> DateTime.add(@invite_expiration_days, :day)

      %UserInvite{}
      |> UserInvite.changeset(%{
        token: token,
        email: email,
        inviter_id: inviter.id,
        expires_at: expires_at
      })
      |> Repo.insert()
      |> handle_invite_insert(inviter)
    else
      {:error, :no_invites_remaining}
    end
  end

  defp handle_invite_insert({:ok, invite}, inviter) do
    if not inviter.is_admin do
      decrement_invites_remaining(inviter)
    end

    {:ok, invite}
  end

  defp handle_invite_insert(error, _inviter), do: error

  @doc """
  Gets an invite by token.
  """
  def get_invite_by_token(token) when is_binary(token) do
    Repo.get_by(UserInvite, token: token)
    |> Repo.preload(:inviter)
  end

  @doc """
  Gets a valid invite by token (not expired and not used).
  """
  def get_valid_invite_by_token(token) when is_binary(token) do
    case get_invite_by_token(token) do
      nil -> nil
      invite -> if UserInvite.valid?(invite), do: invite, else: nil
    end
  end

  @doc """
  Marks an invite as used and associates it with the invitee.
  Returns {:ok, invite} or {:error, changeset}.
  """
  def use_invite(%UserInvite{} = invite, %User{} = invitee) do
    invite
    |> UserInvite.changeset(%{
      invitee_id: invitee.id,
      used_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Lists all invites sent by a user.
  """
  def list_sent_invites(%User{} = user) do
    UserInvite
    |> where([i], i.inviter_id == ^user.id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
    |> Repo.preload(:invitee)
  end

  @doc """
  Gets the count of invites sent by a user.
  """
  def count_sent_invites(%User{} = user) do
    UserInvite
    |> where([i], i.inviter_id == ^user.id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets the count of unused invites sent by a user.
  """
  def count_unused_sent_invites(%User{} = user) do
    UserInvite
    |> where([i], i.inviter_id == ^user.id and is_nil(i.used_at))
    |> Repo.aggregate(:count, :id)
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  defp decrement_invites_remaining(%User{} = user) do
    user
    |> User.changeset(%{invites_remaining: max(0, user.invites_remaining - 1)})
    |> Repo.update()
  end
end

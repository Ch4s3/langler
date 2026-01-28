defmodule Langler.Accounts.UserInvite do
  @moduledoc """
  Ecto schema for user invites.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_invites" do
    field :token, :string
    field :email, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :inviter, Langler.Accounts.User, foreign_key: :inviter_id
    belongs_to :invitee, Langler.Accounts.User, foreign_key: :invitee_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:token, :email, :expires_at, :used_at, :inviter_id, :invitee_id])
    |> validate_required([:token, :email, :expires_at, :inviter_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:token)
  end

  @doc """
  Checks if an invite is valid (not expired and not used).
  """
  def valid?(invite) do
    is_nil(invite.used_at) && DateTime.compare(invite.expires_at, DateTime.utc_now()) == :gt
  end

  @doc """
  Checks if an invite has been used.
  """
  def used?(invite) do
    not is_nil(invite.used_at)
  end

  @doc """
  Checks if an invite has expired.
  """
  def expired?(invite) do
    DateTime.compare(invite.expires_at, DateTime.utc_now()) == :lt
  end
end

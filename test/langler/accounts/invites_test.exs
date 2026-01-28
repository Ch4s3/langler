defmodule Langler.Accounts.InvitesTest do
  use Langler.DataCase, async: true

  import Langler.AccountsFixtures

  alias Langler.Accounts.{Invites, UserInvite}
  alias Langler.Repo

  describe "can_send_invite?/1" do
    test "returns true for admin users" do
      admin = user_fixture()
      admin = Repo.update!(Ecto.Changeset.change(admin, is_admin: true, invites_remaining: 0))
      assert Invites.can_send_invite?(admin)
    end

    test "returns true for non-admin users with invites remaining" do
      user = user_fixture()
      assert Invites.can_send_invite?(user)
    end

    test "returns false for non-admin users with no invites remaining" do
      user = user_fixture()
      user = Repo.update!(Ecto.Changeset.change(user, invites_remaining: 0))
      refute Invites.can_send_invite?(user)
    end
  end

  describe "create_invite/2" do
    test "creates invite for user with invites remaining" do
      user = user_fixture(%{invites_remaining: 3})

      assert {:ok, invite} = Invites.create_invite(user, "test@example.com")
      assert invite.email == "test@example.com"
      assert invite.inviter_id == user.id
      assert invite.token
      assert invite.expires_at
      refute invite.used_at
      refute invite.invitee_id
    end

    test "decrements invites_remaining for non-admin users" do
      user = user_fixture(%{invites_remaining: 3})

      assert {:ok, _invite} = Invites.create_invite(user, "test@example.com")

      updated_user = Repo.reload(user)
      assert updated_user.invites_remaining == 2
    end

    test "does not decrement invites_remaining for admin users" do
      admin = user_fixture()
      admin = Repo.update!(Ecto.Changeset.change(admin, is_admin: true, invites_remaining: 0))

      assert {:ok, _invite} = Invites.create_invite(admin, "test@example.com")

      updated_admin = Repo.reload(admin)
      assert updated_admin.invites_remaining == 0
    end

    test "returns error when user has no invites remaining" do
      user = user_fixture()
      user = Repo.update!(Ecto.Changeset.change(user, invites_remaining: 0))

      assert {:error, :no_invites_remaining} =
               Invites.create_invite(user, "test@example.com")
    end

    test "sets expiration date 7 days in the future" do
      user = user_fixture(%{invites_remaining: 1})
      now = DateTime.utc_now()

      assert {:ok, invite} = Invites.create_invite(user, "test@example.com")

      # Should be approximately 7 days from now
      diff_seconds = DateTime.diff(invite.expires_at, now, :second)
      expected_seconds = 7 * 24 * 60 * 60

      # Allow for some execution time (within 10 seconds)
      assert_in_delta diff_seconds, expected_seconds, 10
    end

    test "generates unique token for each invite" do
      user = user_fixture(%{invites_remaining: 3})

      assert {:ok, invite1} = Invites.create_invite(user, "test1@example.com")
      assert {:ok, invite2} = Invites.create_invite(user, "test2@example.com")

      assert invite1.token != invite2.token
    end

    test "returns error for invalid email" do
      user = user_fixture(%{invites_remaining: 1})

      assert {:error, changeset} = Invites.create_invite(user, "invalid-email")
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end
  end

  describe "get_invite_by_token/1" do
    test "returns invite when token exists" do
      user = user_fixture(%{invites_remaining: 1})
      {:ok, invite} = Invites.create_invite(user, "test@example.com")

      result = Invites.get_invite_by_token(invite.token)

      assert result.id == invite.id
      assert result.inviter.id == user.id
    end

    test "returns nil when token does not exist" do
      assert Invites.get_invite_by_token("nonexistent") == nil
    end
  end

  describe "get_valid_invite_by_token/1" do
    test "returns invite when valid (not used, not expired)" do
      user = user_fixture(%{invites_remaining: 1})
      {:ok, invite} = Invites.create_invite(user, "test@example.com")

      result = Invites.get_valid_invite_by_token(invite.token)

      assert result.id == invite.id
    end

    test "returns nil when invite is used" do
      user = user_fixture(%{invites_remaining: 1})
      invitee = user_fixture()
      {:ok, invite} = Invites.create_invite(user, "test@example.com")
      {:ok, _} = Invites.use_invite(invite, invitee)

      assert Invites.get_valid_invite_by_token(invite.token) == nil
    end

    test "returns nil when invite is expired" do
      user = user_fixture(%{invites_remaining: 1})
      {:ok, invite} = Invites.create_invite(user, "test@example.com")

      # Manually expire the invite
      invite
      |> UserInvite.changeset(%{expires_at: DateTime.add(DateTime.utc_now(), -1, :day)})
      |> Repo.update!()

      assert Invites.get_valid_invite_by_token(invite.token) == nil
    end

    test "returns nil when token does not exist" do
      assert Invites.get_valid_invite_by_token("nonexistent") == nil
    end
  end

  describe "use_invite/2" do
    test "marks invite as used and associates invitee" do
      user = user_fixture(%{invites_remaining: 1})
      invitee = user_fixture()
      {:ok, invite} = Invites.create_invite(user, "test@example.com")

      assert {:ok, updated_invite} = Invites.use_invite(invite, invitee)

      assert updated_invite.invitee_id == invitee.id
      assert updated_invite.used_at
      refute UserInvite.valid?(updated_invite)
    end
  end

  describe "list_sent_invites/1" do
    test "returns all invites sent by user" do
      user = user_fixture(%{invites_remaining: 3})
      {:ok, invite1} = Invites.create_invite(user, "test1@example.com")
      {:ok, invite2} = Invites.create_invite(user, "test2@example.com")

      invites = Invites.list_sent_invites(user)

      assert length(invites) == 2
      assert Enum.any?(invites, &(&1.id == invite1.id))
      assert Enum.any?(invites, &(&1.id == invite2.id))
    end

    test "returns invites ordered by inserted_at desc" do
      user = user_fixture()
      {:ok, _invite1} = Invites.create_invite(user, "test1@example.com")
      :timer.sleep(10)
      {:ok, _invite2} = Invites.create_invite(user, "test2@example.com")

      invites = Invites.list_sent_invites(user)

      # Should have both invites
      assert length(invites) == 2
      emails = Enum.map(invites, & &1.email)
      assert "test1@example.com" in emails
      assert "test2@example.com" in emails
    end

    test "preloads invitee association" do
      user = user_fixture(%{invites_remaining: 1})
      invitee = user_fixture()
      {:ok, invite} = Invites.create_invite(user, "test@example.com")
      {:ok, _} = Invites.use_invite(invite, invitee)

      invites = Invites.list_sent_invites(user)

      assert List.first(invites).invitee.id == invitee.id
    end

    test "returns empty list when user has sent no invites" do
      user = user_fixture(%{invites_remaining: 3})

      assert Invites.list_sent_invites(user) == []
    end
  end

  describe "count_sent_invites/1" do
    test "returns count of all invites sent by user" do
      user = user_fixture(%{invites_remaining: 3})
      {:ok, _} = Invites.create_invite(user, "test1@example.com")
      {:ok, _} = Invites.create_invite(user, "test2@example.com")

      assert Invites.count_sent_invites(user) == 2
    end

    test "returns 0 when user has sent no invites" do
      user = user_fixture(%{invites_remaining: 3})

      assert Invites.count_sent_invites(user) == 0
    end
  end

  describe "count_unused_sent_invites/1" do
    test "returns count of unused invites only" do
      user = user_fixture(%{invites_remaining: 3})
      invitee = user_fixture()
      {:ok, invite1} = Invites.create_invite(user, "test1@example.com")
      {:ok, _invite2} = Invites.create_invite(user, "test2@example.com")
      {:ok, _} = Invites.use_invite(invite1, invitee)

      assert Invites.count_unused_sent_invites(user) == 1
    end

    test "returns 0 when all invites are used" do
      user = user_fixture(%{invites_remaining: 2})
      invitee = user_fixture()
      {:ok, invite1} = Invites.create_invite(user, "test1@example.com")
      {:ok, invite2} = Invites.create_invite(user, "test2@example.com")
      {:ok, _} = Invites.use_invite(invite1, invitee)
      {:ok, _} = Invites.use_invite(invite2, invitee)

      assert Invites.count_unused_sent_invites(user) == 0
    end
  end
end

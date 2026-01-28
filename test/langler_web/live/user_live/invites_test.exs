defmodule LanglerWeb.UserLive.InvitesTest do
  use LanglerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Langler.AccountsFixtures

  alias Langler.Accounts.Invites
  alias Langler.Repo

  setup :register_and_log_in_user

  # Note: This test file requires proper routing setup for invites page
  # If the route doesn't exist yet, these tests will need to be updated

  describe "mount/3" do
    test "loads user invites and status", %{conn: conn, user: user} do
      {:ok, _invite} = Invites.create_invite(user, "test@example.com")

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert has_element?(view, "#invite-form")
      assert render(view) =~ "test@example.com"
    end

    test "shows admin unlimited invites message", %{conn: conn, user: user} do
      user = Repo.update!(Ecto.Changeset.change(user, is_admin: true))
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert render(view) =~ "unlimited invites"
    end

    test "shows remaining invites for regular users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert render(view) =~ "3 invites remaining"
    end
  end

  describe "send_invite event" do
    test "sends invite and updates list", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/invites")

      # Use phx-submit event directly since form params don't match handle_event
      view
      |> render_hook("send_invite", %{email: "newuser@example.com"})

      assert render(view) =~ "Invite sent"
      assert render(view) =~ "newuser@example.com"

      # Check invites were decremented
      updated_user = Repo.reload(user)
      assert updated_user.invites_remaining == 2
    end

    test "shows error when no invites remaining", %{conn: conn, user: user} do
      user = Repo.update!(Ecto.Changeset.change(user, invites_remaining: 0))
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      refute has_element?(view, "#invite-form")
      assert render(view) =~ "used all your invites"
    end

    test "validates email format", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/invites")

      # Use phx-change event directly
      view
      |> render_hook("validate", %{email: "invalid-email"})

      assert render(view) =~ "must have the @ sign"
    end
  end

  describe "invites display" do
    test "shows pending invite status", %{conn: conn, user: user} do
      {:ok, _invite} = Invites.create_invite(user, "pending@example.com")

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert render(view) =~ "Pending"
    end

    test "shows used invite status", %{conn: conn, user: user} do
      invitee = user_fixture()
      {:ok, invite} = Invites.create_invite(user, "used@example.com")
      {:ok, _} = Invites.use_invite(invite, invitee)

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert render(view) =~ "Used"
    end

    test "shows expired invite status", %{conn: conn, user: user} do
      {:ok, invite} = Invites.create_invite(user, "expired@example.com")

      # Manually expire the invite - use DateTime.truncate to remove microseconds
      expires_at = DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)

      invite
      |> Ecto.Changeset.change(expires_at: expires_at)
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/users/invites")

      assert render(view) =~ "Expired"
    end

    test "shows empty state when no invites sent", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/invites")

      # User starts with default invites_remaining but hasn't sent any
      assert has_element?(view, "#invite-form")
      refute has_element?(view, "table")
    end
  end
end

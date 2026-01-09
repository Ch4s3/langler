defmodule Langler.AccountsTest do
  use Langler.DataCase, async: true

  alias Langler.Accounts
  alias Langler.AccountsFixtures

  test "create_user/1 persists a user" do
    assert {:ok, user} =
             Accounts.create_user(%{email: "unique@example.com", name: "Jane"})

    assert user.email == "unique@example.com"
  end

  test "upsert_user_preference/2 creates and updates preferences" do
    user = AccountsFixtures.user_fixture()

    assert {:ok, pref} =
             Accounts.upsert_user_preference(user, %{
               target_language: "spanish",
               native_language: "en"
             })

    assert pref.target_language == "spanish"

    assert {:ok, updated} = Accounts.upsert_user_preference(user, %{target_language: "french"})
    assert updated.target_language == "french"
  end
end

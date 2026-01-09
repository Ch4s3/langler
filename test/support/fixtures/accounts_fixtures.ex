defmodule Langler.AccountsFixtures do
  alias Langler.Accounts

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "user#{System.unique_integer([:positive])}@example.com",
        name: "Test User"
      })
      |> Accounts.create_user()

    user
  end
end

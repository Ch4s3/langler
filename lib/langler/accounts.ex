defmodule Langler.Accounts do
  @moduledoc """
  Account management (users + preferences).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Accounts.{User, UserPreference}

  def list_users, do: Repo.all(User)

  def get_user!(id), do: Repo.get!(User, id)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def get_user_preference(user_id) do
    Repo.get_by(UserPreference, user_id: user_id)
  end

  def upsert_user_preference(user, attrs) do
    pref = get_user_preference(user.id) || %UserPreference{user_id: user.id}

    pref
    |> UserPreference.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert_or_update()
  end

  def ensure_demo_user do
    case Repo.one(from u in User, limit: 1) do
      nil ->
        case create_user(%{email: "demo@langler.app", name: "Demo User"}) do
          {:ok, user} -> user
          {:error, _} -> Repo.one!(from u in User, limit: 1)
        end

      user ->
        user
    end
  end
end

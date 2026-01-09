defmodule Langler.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string

    has_many :article_users, Langler.Content.ArticleUser
    has_many :articles, through: [:article_users, :article]
    has_many :fsrs_items, Langler.Study.FSRSItem
    has_one :preference, Langler.Accounts.UserPreference

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end
end

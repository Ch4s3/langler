defmodule Langler.Accounts.UserInterestTag do
  @moduledoc """
  Ecto schema for user interest tags selected during onboarding.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_interest_tags" do
    field :tag, :string
    field :language, :string, default: "spanish"
    belongs_to :user, Langler.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(user_interest_tag, attrs) do
    user_interest_tag
    |> cast(attrs, [:user_id, :tag, :language])
    |> validate_required([:user_id, :tag, :language])
    |> unique_constraint([:user_id, :tag, :language])
  end
end

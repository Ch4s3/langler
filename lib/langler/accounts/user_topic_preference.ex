defmodule Langler.Accounts.UserTopicPreference do
  @moduledoc """
  Ecto schema for user topic preferences.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_topic_preferences" do
    field :topic, :string
    field :weight, :decimal
    belongs_to :user, Langler.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(user_topic_preference, attrs) do
    user_topic_preference
    |> cast(attrs, [:user_id, :topic, :weight])
    |> validate_required([:user_id, :topic, :weight])
    |> validate_number(:weight, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)
    |> unique_constraint([:user_id, :topic])
  end
end

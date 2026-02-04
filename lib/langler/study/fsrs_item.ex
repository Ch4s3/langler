defmodule Langler.Study.FSRSItem do
  @moduledoc """
  Ecto schema for FSRS study items.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "fsrs_items" do
    field :ease_factor, :float, default: 2.5
    field :interval, :integer, default: 0
    field :due_date, :utc_datetime
    field :repetitions, :integer, default: 0
    field :quality_history, {:array, :integer}, default: []
    field :last_reviewed_at, :utc_datetime
    field :stability, :float
    field :difficulty, :float
    field :retrievability, :float
    field :state, :string, default: "learning"
    field :step, :integer

    belongs_to :user, Langler.Accounts.User
    belongs_to :word, Langler.Vocabulary.Word
    belongs_to :custom_card, Langler.Vocabulary.CustomCard

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :ease_factor,
      :interval,
      :due_date,
      :repetitions,
      :quality_history,
      :last_reviewed_at,
      :stability,
      :difficulty,
      :retrievability,
      :state,
      :step,
      :user_id,
      :word_id,
      :custom_card_id
    ])
    |> validate_required([:user_id])
    |> validate_word_or_custom_card()
    |> unique_constraint([:user_id, :word_id])
    |> unique_constraint([:user_id, :custom_card_id])
    |> assoc_constraint(:user)
  end

  defp validate_word_or_custom_card(changeset) do
    word_id = Ecto.Changeset.get_field(changeset, :word_id)
    custom_card_id = Ecto.Changeset.get_field(changeset, :custom_card_id)

    cond do
      word_id && custom_card_id ->
        add_error(changeset, :base, "Cannot set both word_id and custom_card_id")

      is_nil(word_id) && is_nil(custom_card_id) ->
        add_error(changeset, :base, "Must set either word_id or custom_card_id")

      true ->
        changeset
    end
  end
end

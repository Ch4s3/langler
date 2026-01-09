defmodule Langler.Study.FSRSItem do
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
      :word_id
    ])
    |> validate_required([:user_id, :word_id])
    |> unique_constraint([:user_id, :word_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:word)
  end
end

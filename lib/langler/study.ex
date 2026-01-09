defmodule Langler.Study do
  @moduledoc """
  Study mode context (FSRS items + helpers).
  """

  import Ecto.Query, warn: false
  alias Langler.Repo

  alias Langler.Study.{FSRS, FSRSItem}

  def list_items_for_user(user_id) do
    FSRSItem
    |> where(user_id: ^user_id)
    |> order_by([i], asc: i.due_date)
    |> Repo.all()
    |> Repo.preload(:word)
  end

  def due_items(user_id, reference_datetime \\ DateTime.utc_now()) do
    FSRSItem
    |> where([i], i.user_id == ^user_id)
    |> where([i], not is_nil(i.due_date) and i.due_date <= ^reference_datetime)
    |> order_by([i], asc: i.due_date)
    |> Repo.all()
  end

  def get_item!(id), do: Repo.get!(FSRSItem, id)

  def get_item_by_user_and_word(user_id, word_id) do
    Repo.get_by(FSRSItem, user_id: user_id, word_id: word_id)
  end

  def create_item(attrs \\ %{}) do
    %FSRSItem{}
    |> FSRSItem.changeset(attrs)
    |> Repo.insert()
  end

  def update_item(%FSRSItem{} = item, attrs) do
    item
    |> FSRSItem.changeset(attrs)
    |> Repo.update()
  end

  def change_item(%FSRSItem{} = item, attrs \\ %{}) do
    FSRSItem.changeset(item, attrs)
  end

  def append_quality(%FSRSItem{} = item, quality_score, attrs \\ %{}) do
    history = (item.quality_history || []) ++ [quality_score]
    attrs = attrs |> Enum.into(%{}) |> Map.put(:quality_history, history)

    update_item(item, attrs)
  end

  def to_scheduler_item(%FSRSItem{} = record, overrides \\ []) do
    record
    |> Map.from_struct()
    |> Map.drop([:__meta__, :user, :word])
    |> FSRS.item(overrides)
  end
end
